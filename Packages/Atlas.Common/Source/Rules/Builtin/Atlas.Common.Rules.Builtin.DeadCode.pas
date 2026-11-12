unit Atlas.Common.Rules.Builtin.DeadCode;

// Toter Code und zirkuläre Unit-Abhängigkeiten (#64):
//   uses-cycle          Ein uses-Eintrag, über den ein Weg zurück zur eigenen
//                       Unit führt (Gruppe Architektur). Liegt jede Kante im
//                       interface-Teil, ist es ein Fehler wie F2047; Zyklen mit
//                       mindestens einer implementation-Kante sind erlaubt und
//                       erscheinen mit dem Schweregrad der Regel (Option
//                       implementation, Vorgabe an). Die Meldung nennt den
//                       vollständigen kürzesten Pfad, der Befund-Hover jede
//                       Kante mit ihrem Abschnitt. Grundlage ist der
//                       gemeinsame Uses-Graph (#268) über IRuleProjectFiles;
//                       für die eigene Unit gilt der Editor-Stand, für
//                       andere offene Units ihr Puffer nach der Tipp-Pause.
//                       Im Editor (TRuleContext.Live, #896) schaltet
//                       diagnostics.usesCycleLive die Meldung ab, Zyklen mit
//                       implementation-Kante erscheinen dort nur mit
//                       diagnostics.usesCycleImplementation, als Hinweis.
//                       Jede Unit des Pfads trägt die Stelle ihres
//                       uses-Eintrags (TRuleRelated, Sprung aus dem Hover).
//                       Korrekturen am interface-Eintrag: „In
//                       implementation-uses verschieben“, wenn kein
//                       Bezeichner der Unit im interface-Teil gebraucht wird
//                       (sortiert mit sortUses), sonst Sprünge zu diesen
//                       Bezeichnern und „Graph zeigen“ (Unit-Beziehungen,
//                       #593). Ein Selbstverweis ist immer ein Fehler.
//   unused-declaration  Routine, Typ, Konstante oder globale Variable aus dem
//                       implementation-Teil (bzw. einem Programm), die in der
//                       Unit nirgends vorkommt. Keine Verwendung sind die
//                       eigenen Deklarationen, Vorkommen im eigenen Rumpf
//                       (Rekursion) und bei Typen in der eigenen Deklaration
//                       und den Rümpfen der eigenen Methoden samt Kopf
//                       (TTyp.Name). Ausnahmen aus dem Dienst „gilt als
//                       verwendet“ (exports, Attribute, deadCode.keep*), Namen
//                       aus der Formulardatei; Units mit Include-Dateien
//                       schweigen. Die Deklarationen des interface-Teils
//                       prüft unused-public-member projektweit.
//   unused-unit         Unit einer Anwendung, die keine andere Unit verwendet:
//                       Höchstens Programme nennen sie im uses und verwenden
//                       außerhalb ihres uses keinen ihrer Bezeichner (z. B.
//                       Application.CreateForm(TForm1, Form1)). Units mit
//                       initialization- oder finalization-Teil (Registrierung)
//                       gelten als verwendet, ebenso Units mit einer Klasse
//                       [TestFixture], die DUnitX per RTTI findet
//                       ({$STRONGLINKTYPES ON}). Packages und DLLs haben Nutzer
//                       außerhalb der Gruppe (Option projectKinds).
//   unused-uses         uses-Eintrag, aus dessen Unit nichts verwendet wird
//                       (#1352), mit derselben Analyse wie die Hinweise im
//                       Editor (#621, TUsesActions.Entries) samt
//                       Namensauflösung (#1925, TUsesUsage): Units, die der
//                       Index nicht kennt, mit initialization/finalization
//                       oder aus usesKeep und der Option keep (#1135)
//                       bleiben; inaktive Zweige zählen
//                       nicht; nur in Units, denn das uses eines Programms
//                       oder Packages zählt die Units des Projekts auf.
//                       Sichere Korrektur „Eintrag entfernen“ für die
//                       Sammelkorrektur (--fix unused-uses). Im Editor
//                       (TRuleContext.Live) läuft die Regel nicht
//                       (IRuleCondition), dort zeigt der Server dieselben
//                       Einträge abgeblendet, nach ihren Einstellungen
//                       (TLspSyntaxDiagnostics.AddUnusedUses); ohne Index und
//                       bei Syntaxfehlern ebenso.
//   uses-only-in-implementation
//                       Eintrag im interface-uses, dessen Unit nur der
//                       implementation-Teil braucht (#1136), mit derselben
//                       Analyse (TUsesEntryState.OnlyImplementation). Units
//                       mit initialization/finalization bleiben, denn ihre
//                       Reihenfolge zählt. Korrektur „In implementation-uses
//                       verschieben“ (sortiert mit sortUses), nicht sicher:
//                       Im implementation-uses steht die Unit später und kann
//                       gleichnamige Bezeichner anderer Units verdecken. Wann
//                       sie läuft und die Darstellung im Editor wie bei
//                       unused-uses.
//
// uses-cycle und unused-unit schweigen ohne Projekte (Linter, Datei ohne
// Projekt), solange Projekte laden oder der Index läuft, und für Units, die der
// Uses-Graph nicht kennt.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cUsesCycleRuleId = 'uses-cycle';
  cUnusedDeclarationRuleId = 'unused-declaration';
  cUnusedUnitRuleId = 'unused-unit';
  cUnusedUsesRuleId = 'unused-uses';
  cUsesOnlyInImplementationRuleId = 'uses-only-in-implementation';

type
  TUsesCycleRule = class(TInterfacedObject, IRule, IRuleCondition)
  public
    function Descriptor: TRuleDescriptor;
    /// <summary>Nicht beim Tippen mit diagnostics.usesCycleLive aus (#896).</summary>
    function Applies(const AContext: TRuleContext): Boolean;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedDeclarationRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedUnitRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedUsesRule = class(TInterfacedObject, IRule, IRuleCondition)
  public
    function Descriptor: TRuleDescriptor;
    /// <summary>Nicht im Editor (dort blendet der Server dieselben Einträge ab), ohne Index, bei Syntaxfehlern und
    /// außerhalb von Units.</summary>
    function Applies(const AContext: TRuleContext): Boolean;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Units, die bleiben: AUsesKeep (usesKeep) und die Option keep der Regel aus AOptions (#1135).
    /// </summary>
    class function Keep(const AOptions: string; const AUsesKeep: TArray<string>): TArray<string>; static;
  end;

  TUsesOnlyInImplementationRule = class(TInterfacedObject, IRule, IRuleCondition)
  public
    function Descriptor: TRuleDescriptor;
    /// <summary>Wie unused-uses: nicht im Editor (dort zeigt der Server denselben Hinweis), ohne Index, bei
    /// Syntaxfehlern und außerhalb von Units.</summary>
    function Applies(const AContext: TRuleContext): Boolean;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDeadCodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.UsesUsage,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Common.Rules.Builtin.Units,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeadCodeText = (MoveToImplementation, NeededInInterface, RemoveEntry, Circular, LikeF2092, SelfUses, AllInterface,
    OneImplementation, ShowGraph, LikeF2047, ViaImplementation, CycleTitle, Routine, Constant, GlobalVariable,
    TypeWord, MarkIntended, NeverUsed, UnusedTitle, UnitTitle, UnitUnused, UnitOnlyBy, UsesTitle, NothingUsed, JumpTo,
    LineSuffix, PlacementTitle, OnlyImplementation);

const
  cTexts: array[TDeadCodeText] of TAtlasText = (
    (De: 'In implementation-uses verschieben'; En: 'Move to implementation uses'),
    (De: 'Im interface-Teil gebraucht: '; En: 'Needed in the interface part: '),
    (De: 'Eintrag entfernen'; En: 'Remove entry'),
    (De: 'Zirkuläre Unit-Referenz: '; En: 'Circular unit reference: '),
    (De: ' (wie F2092)'; En: ' (like F2092)'),
    (De: 'Die Unit nennt sich selbst im uses: Der Compiler lehnt das ab (F2092).';
     En: 'The unit names itself in uses: the compiler rejects that (F2092).'),
    (De: 'Alle Kanten liegen im interface-Teil: Der Compiler lehnt den Zyklus ab (F2047).';
     En: 'All edges are in the interface part: the compiler rejects the cycle (F2047).'),
    (De: 'Mindestens eine Kante liegt im implementation-Teil: Der Compiler erlaubt den Zyklus.';
     En: 'At least one edge is in the implementation part: the compiler allows the cycle.'),
    (De: 'Graph zeigen (Unit-Beziehungen)'; En: 'Show graph (unit relations)'),
    (De: ' (wie F2047)'; En: ' (like F2047)'),
    (De: ' (über implementation-uses)'; En: ' (via implementation uses)'),
    (De: 'Zirkuläre Unit-Referenz über uses'; En: 'Circular unit reference via uses'),
    (De: 'Routine'; En: 'Routine'),
    (De: 'Konstante'; En: 'Constant'),
    (De: 'Globale Variable'; En: 'Global variable'),
    (De: 'Typ'; En: 'Type'),
    (De: 'Als bewusst vorhanden markieren (lsp-ignore)'; En: 'Mark as intentionally present (lsp-ignore)'),
    (De: '%s %s wird nirgends verwendet.'; En: '%s %s is never used.'),
    (De: 'Deklaration im implementation-Teil wird nie verwendet';
     En: 'Declaration in the implementation part is never used'),
    (De: 'Unit wird von keiner anderen Unit verwendet'; En: 'Unit is not used by any other unit'),
    (De: 'Unit %s wird von keiner Unit und keinem Programm verwendet.';
     En: 'Unit %s is used by no unit and no program.'),
    (De: 'Unit %s wird von keiner anderen Unit verwendet; nur %s nennt sie im uses.';
     En: 'Unit %s is not used by any other unit; only %s names it in uses.'),
    (De: 'Aus der Unit im uses wird nichts verwendet'; En: 'Nothing from the unit in uses is used'),
    (De: 'Aus %s wird nichts verwendet'; En: 'Nothing from %s is used'),
    (De: 'Zu %s springen (Zeile %s, braucht %s im interface)'; En: 'Go to %s (line %s, needs %s in the interface)'),
    (De: ' (Zeile %s)'; En: ' (line %s)'),
    (De: 'Unit gehört in die uses des implementation-Teils'; En: 'Unit belongs in the uses of the implementation part'),
    (De: '%s wird nur im implementation-Teil gebraucht'; En: '%s is only needed in the implementation part'));

{$SCOPEDENUMS OFF}

function CleanName(const AText: string): string;
begin
  if StartsStr('&', AText) then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

function SamePosition(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

/// <summary>Liegt A an oder hinter B?</summary>
function NotBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line > B.Line) or (A.Line = B.Line) and (A.Character >= B.Character);
end;

function Inside(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in ARanges do
  begin
    if NotBefore(APosition, mRange.StartPos) and NotBefore(mRange.EndPos, APosition) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function HasIncludes(const ATree: TSyntaxTree): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  for mToken in ATree.Tokens do
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

/// <summary>Trägt die Unit das Attribut [TestFixture]? DUnitX findet solche Klassen per RTTI, ohne dass eine
/// Unit sie nennt oder registriert.</summary>
function HasTestFixture(const ATokens: TArray<TPascalToken>): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 1 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, 'TestFixture') and
      ATokens[mIndex - 1].IsSymbol('[') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsProgramFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk');
end;

function IsTypeKind(AKind: TIndexSymbolKind): Boolean;
begin
  Result := AKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
end;

function ProjectKindKey(AKind: TRuleProjectKind): string;
begin
  case AKind of
    TRuleProjectKind.Application:
      Result := 'application';
    TRuleProjectKind.Package:
      Result := 'package';
    TRuleProjectKind.Library_:
      Result := 'library';
  else
    Result := '';
  end;
end;

/// <summary>Bereich des Unit-Namens im Kopf (unit A.B.C;); leer, wenn die Datei keine Unit ist.</summary>
function UnitNameRange(const ATokens: TArray<TPascalToken>; out ARange: TTextRange): Boolean;
var
  mIndex, mLast: Integer;
begin
  Result := False;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if not SameText(ATokens[mIndex].Text, 'unit') then
    begin
      Exit;
    end;
    mLast := mIndex + 1;
    while (mLast + 2 <= High(ATokens)) and ATokens[mLast + 1].IsSymbol('.') and
      (ATokens[mLast + 2].Kind = TPascalTokenKind.Identifier) do
    begin
      Inc(mLast, 2);
    end;
    if (mLast > High(ATokens)) or (ATokens[mIndex + 1].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    ARange := TTextRange.Create(ATokens[mIndex + 1].StartPos, ATokens[mLast].EndPos);
    Exit(True);
  end;
end;

/// <summary>Kleinste Ersetzung, die AOld in ANew verwandelt (gemeinsamer Anfang und Schluss bleiben).</summary>
function SmallestEdit(const AOld, ANew: string): TTextEdit;
var
  mPrefix, mSuffix: Integer;
  mLines: TLineTable;
begin
  mPrefix := 0;
  while (mPrefix < Length(AOld)) and (mPrefix < Length(ANew)) and (AOld[mPrefix + 1] = ANew[mPrefix + 1]) do
  begin
    Inc(mPrefix);
  end;
  mSuffix := 0;
  while (mSuffix < Length(AOld) - mPrefix) and (mSuffix < Length(ANew) - mPrefix) and
    (AOld[Length(AOld) - mSuffix] = ANew[Length(ANew) - mSuffix]) do
  begin
    Inc(mSuffix);
  end;
  mLines := TLineTable.Build(AOld);
  Result := TTextEdit.Create(TTextRange.Create(mLines.PositionAt(mPrefix), mLines.PositionAt(Length(AOld) - mSuffix)),
    Copy(ANew, mPrefix + 1, Length(ANew) - mPrefix - mSuffix));
end;

/// <summary>„In implementation-uses verschieben“ (sortiert wie sortUses), geteilt von uses-cycle und
/// uses-only-in-implementation; nil, wenn das uses es nicht zulässt.</summary>
function MoveToImplementationFixes(const AContext: TRuleContext; const AUnitName: string): TArray<TRuleFix>;
var
  mEdits, mSortEdits: TArray<TTextEdit>;
  mLineBreak, mNewText: string;
begin
  Result := nil;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  if not TUsesActions.MoveUnits(AContext.Tree.Tokens, AContext.Text, TArray<string>.Create(AUnitName), mLineBreak,
    mEdits) then
  begin
    Exit;
  end;
  if AContext.SortUses then
  begin
    // Wie „uses aufräumen“ mit sortUses: erst verschieben, dann sortieren, als eine kleinste Ersetzung.
    mNewText := TChangeSignature.ApplyEdits(AContext.Text, mEdits);
    if TUsesClauses.Organize(TPascalLexer.Tokenize(mNewText), mNewText, True, mLineBreak, mSortEdits,
      AContext.SortUsesByNamespace) then
    begin
      mNewText := TChangeSignature.ApplyEdits(mNewText, mSortEdits);
    end;
    mEdits := TArray<TTextEdit>.Create(SmallestEdit(AContext.Text, mNewText));
  end;
  Result := TArray<TRuleFix>.Create(TRuleFix.Create(cTexts[TDeadCodeText.MoveToImplementation].Text, mEdits));
end;

{ TUsesCycleCheck }

type
  /// <summary>Ein Lauf von uses-cycle über eine Datei: Selbstverweise, dann Zyklen je uses-Eintrag.</summary>
  TUsesCycleCheck = class
  private const
    // Höchstens so viele Sprünge zu Bezeichnern, die die Unit im interface brauchen (#896).
    cMaxJumps = 5;
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FOwnName: string;
    FWithImplementation: Boolean;
    // Datei (groß) -> uses-Einträge, je Prüfung einmal gelesen.
    FEntries: TDictionary<string, TArray<TUsesReference>>;
    function EntryRange(const AFileName, AUsesName: string; AInInterface: Boolean): TTextRange;
    function JumpFixes(const AUnitName: string; const AShown: TArray<TUsesInterfaceUsage>;
      var ADetails: string): TArray<TRuleFix>;
    function InterfaceFixes(const AUnitName: string; var ADetails: string): TArray<TRuleFix>;
    procedure AddFinding(const ARange: TTextRange; const AMessage, ADetails: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
    function RemoveFixes(const ARange: TTextRange): TArray<TRuleFix>;
    procedure CheckSelfReferences;
    function CycleSteps(const AReference: TUsesReference; out AAllInterface: Boolean): TArray<TRuleUsesStep>;
    function PathRelated(const AReference: TUsesReference; const ASteps: TArray<TRuleUsesStep>;
      var APathText, ADetails: string): TArray<TRuleRelated>;
    procedure ReportCycle(const AReference: TUsesReference; const ASteps: TArray<TRuleUsesStep>;
      AAllInterface: Boolean);
    procedure CheckReference(const AReference: TUsesReference);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function SectionText(AInInterface: Boolean): string;
begin
  if AInInterface then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
end;

function RelatedOf(const AFileName: string; const ARange: TTextRange; const AUnitName: string): TRuleRelated;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.Message := AUnitName;
end;

/// <summary>Namen des interface-Teils von AUnit: alle (AAllNames) und nur die obersten ohne Container
/// (ATopNames: Typen, Routinen, Konstanten).</summary>
procedure InterfaceNames(const AUnit: TUnitIndex; out AAllNames, ATopNames: TArray<string>);
var
  mSymbol: TIndexSymbol;
begin
  AAllNames := nil;
  ATopNames := nil;
  for mSymbol in AUnit.Symbols do
  begin
    if mSymbol.InInterface then
    begin
      AAllNames := AAllNames + [mSymbol.Name];
      if mSymbol.Container = '' then
      begin
        ATopNames := ATopNames + [mSymbol.Name];
      end;
    end;
  end;
end;

constructor TUsesCycleCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FEntries := TDictionary<string, TArray<TUsesReference>>.Create;
end;

destructor TUsesCycleCheck.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

/// <summary>Stelle des Eintrags AUsesName im Abschnitt AInInterface von AFileName; die eigene Datei im
/// Editor-Stand, andere über ReadText (offene Dokumente zuerst). Ohne Fund der Anfang der Datei.</summary>
function TUsesCycleCheck.EntryRange(const AFileName, AUsesName: string; AInInterface: Boolean): TTextRange;
var
  mText: string;
  mFound: TArray<TUsesReference>;
  mEntry: TUsesReference;
begin
  if not FEntries.TryGetValue(UpperCase(AFileName), mFound) then
  begin
    mFound := nil;
    if SameText(AFileName, FContext.FileName) then
    begin
      mFound := TUsesClauses.References(FContext.Tree.Tokens);
    end
    else if FContext.ProjectFiles.ReadText(AFileName, mText) then
    begin
      mFound := TUsesClauses.References(TPascalLexer.Tokenize(mText));
    end;
    FEntries.Add(UpperCase(AFileName), mFound);
  end;
  for mEntry in mFound do
  begin
    if (mEntry.List = TUsesListKind.UsesList) and (mEntry.InInterface = AInInterface) and
      SameText(mEntry.Name, AUsesName) then
    begin
      Exit(mEntry.Range);
    end;
  end;
  Result := Default(TTextRange);
end;

/// <summary>Sprünge zu den Bezeichnern in AShown (höchstens cMaxJumps), ihre Liste in ADetails.</summary>
function TUsesCycleCheck.JumpFixes(const AUnitName: string; const AShown: TArray<TUsesInterfaceUsage>;
  var ADetails: string): TArray<TRuleFix>;
var
  mName, mNeed, mLine: string;
  mFix: TRuleFix;
  mIndex: Integer;
begin
  Result := nil;
  mNeed := '';
  for mIndex := 0 to High(AShown) do
  begin
    if mIndex >= cMaxJumps then
    begin
      mNeed := mNeed + ', …';
      Break;
    end;
    mName := AShown[mIndex].Name;
    mLine := IntToStr(AShown[mIndex].Range.StartPos.Line + 1);
    if mNeed <> '' then
    begin
      mNeed := mNeed + ', ';
    end;
    mNeed := mNeed + mName + cTexts[TDeadCodeText.LineSuffix].Fmt([mLine]);
    mFix := TRuleFix.Jump(cTexts[TDeadCodeText.JumpTo].Fmt([mName, mLine, AUnitName]), AShown[mIndex].Range.StartPos);
    mFix.Alternative := mIndex > 0;
    Result := Result + [mFix];
  end;
  ADetails := ADetails + sLineBreak + cTexts[TDeadCodeText.NeededInInterface].Text + mNeed;
end;

/// <summary>Korrekturen am interface-Eintrag (#896): ins implementation-uses verschieben, wenn kein
/// Bezeichner der Unit im interface-Teil gebraucht wird (sortiert wie sortUses); sonst Sprünge zu diesen
/// Bezeichnern, ihre Liste in ADetails und „Graph zeigen“.</summary>
function TUsesCycleCheck.InterfaceFixes(const AUnitName: string; var ADetails: string): TArray<TRuleFix>;
var
  mUnitIndex: TUnitIndex;
  mAllNames, mTopNames: TArray<string>;
  mNeeded, mShown: TArray<TUsesInterfaceUsage>;
begin
  Result := nil;
  if (FContext.Index = nil) or not FContext.Index.FindUnit(AUnitName, mUnitIndex) then
  begin
    Exit;
  end;
  InterfaceNames(mUnitIndex, mAllNames, mTopNames);
  mNeeded := TUsesActions.InterfaceUsages(FContext.Tree.Tokens, AUnitName, mAllNames);
  if mNeeded = nil then
  begin
    Exit(MoveToImplementationFixes(FContext, AUnitName));
  end;
  // Erst die Typen, Routinen und Konstanten der Unit; nur Mitglieder (Create, Count) sind unsicherer.
  mShown := TUsesActions.InterfaceUsages(FContext.Tree.Tokens, AUnitName, mTopNames);
  if mShown = nil then
  begin
    mShown := mNeeded;
  end;
  Result := JumpFixes(AUnitName, mShown, ADetails);
end;

/// <summary>Über die Erweiterung des Reports mit den Stellen des Pfads; ohne sie (Test-Doubles) ohne.</summary>
procedure TUsesCycleCheck.AddFinding(const ARange: TTextRange; const AMessage, ADetails: string;
  ASeverity: TRuleSeverity; const AFixes: TArray<TRuleFix>; const ARelated: TArray<TRuleRelated>);
var
  mExtended: IRuleRelatedReport;
begin
  if Supports(FReport, IRuleRelatedReport, mExtended) then
  begin
    mExtended.AddRelated(ARange, AMessage, ADetails, ASeverity, AFixes, ARelated);
  end
  else
  begin
    FReport.AddWithSeverity(ARange, AMessage, ASeverity, AFixes);
  end;
end;

/// <summary>„Eintrag entfernen“ für einen Selbstverweis; nil, wenn die Liste das nicht zulässt.</summary>
function TUsesCycleCheck.RemoveFixes(const ARange: TTextRange): TArray<TRuleFix>;
var
  mEdit: TTextEdit;
begin
  Result := nil;
  if TUsesActions.RemoveEntries(FContext.Text, TArray<TTextRange>.Create(ARange), mEdit) then
  begin
    Result := TArray<TRuleFix>.Create(TRuleFix.Create(cTexts[TDeadCodeText.RemoveEntry].Text,
      TArray<TTextEdit>.Create(mEdit)));
  end;
end;

/// <summary>Selbstverweis (#896): braucht keinen Graphen und ist immer ein Compilerfehler.</summary>
procedure TUsesCycleCheck.CheckSelfReferences;
var
  mReference: TUsesReference;
begin
  for mReference in TUsesClauses.References(FContext.Tree.Tokens) do
  begin
    if (mReference.List = TUsesListKind.UsesList) and SameText(CleanName(mReference.Name), FOwnName) then
    begin
      AddFinding(mReference.Range, cTexts[TDeadCodeText.Circular].Text + FOwnName + ' → ' + FOwnName +
        cTexts[TDeadCodeText.LikeF2092].Text,
        cTexts[TDeadCodeText.SelfUses].Text, TRuleSeverity.Error,
        RemoveFixes(mReference.Range), TArray<TRuleRelated>.Create(RelatedOf(FContext.FileName, mReference.Range,
        FOwnName)));
    end;
  end;
end;

/// <summary>Kürzester Weg von AReference zurück zur eigenen Unit; erst nur über interface (ein solcher
/// Zyklus ist ein Compilerfehler und geht vor), dann mit implementation-Kanten.</summary>
function TUsesCycleCheck.CycleSteps(const AReference: TUsesReference;
  out AAllInterface: Boolean): TArray<TRuleUsesStep>;
begin
  Result := nil;
  if AReference.InInterface then
  begin
    Result := FContext.ProjectFiles.UsesPath(AReference.Name, FContext.FileName, True);
  end;
  AAllInterface := Result <> nil;
  if (Result = nil) and FWithImplementation then
  begin
    Result := FContext.ProjectFiles.UsesPath(AReference.Name, FContext.FileName, False);
  end;
end;

/// <summary>Pfadtext und Kanten in ADetails ergänzen; liefert die Stellen des Pfads. Jede Unit des Pfads
/// springt im Hover an ihren uses-Eintrag (#896); die eigene an den letzten.</summary>
function TUsesCycleCheck.PathRelated(const AReference: TUsesReference; const ASteps: TArray<TRuleUsesStep>;
  var APathText, ADetails: string): TArray<TRuleRelated>;
var
  mStep: TRuleUsesStep;
  mPrevious: string;
begin
  // Verkettet statt Format: Der Pfeil bleibt so auch unter FPC ein Zeichen.
  APathText := FOwnName + ' → ' + AReference.Name;
  ADetails := ADetails + sLineBreak + FOwnName + ' → ' + AReference.Name + ' (' +
    SectionText(AReference.InInterface) + ')';
  Result := TArray<TRuleRelated>.Create(RelatedOf(FContext.FileName, AReference.Range, AReference.Name));
  mPrevious := AReference.Name;
  for mStep in ASteps do
  begin
    APathText := APathText + ' → ' + mStep.UnitName;
    ADetails := ADetails + sLineBreak + mPrevious + ' → ' + mStep.UnitName + ' (' +
      SectionText(mStep.InInterface) + ')';
    Result := Result + [RelatedOf(mStep.SourceFileName, EntryRange(mStep.SourceFileName, mStep.UsesName,
      mStep.InInterface), mStep.UnitName)];
    mPrevious := mStep.UnitName;
  end;
  Result := TArray<TRuleRelated>.Create(RelatedOf(Result[High(Result)].FileName, Result[High(Result)].Range,
    FOwnName)) + Result;
end;

procedure TUsesCycleCheck.ReportCycle(const AReference: TUsesReference; const ASteps: TArray<TRuleUsesStep>;
  AAllInterface: Boolean);
var
  mPathText, mDetails: string;
  mRelated: TArray<TRuleRelated>;
  mFixes: TArray<TRuleFix>;
begin
  if AAllInterface then
  begin
    mDetails := cTexts[TDeadCodeText.AllInterface].Text;
  end
  else
  begin
    mDetails := cTexts[TDeadCodeText.OneImplementation].Text;
  end;
  mRelated := PathRelated(AReference, ASteps, mPathText, mDetails);
  mFixes := nil;
  if AReference.InInterface then
  begin
    mFixes := InterfaceFixes(AReference.Name, mDetails);
  end;
  if (mFixes = nil) or mFixes[0].HasJump then
  begin
    mFixes := mFixes + [TRuleFix.UnitRelations(cTexts[TDeadCodeText.ShowGraph].Text)];
  end;
  if AAllInterface then
  begin
    AddFinding(AReference.Range, cTexts[TDeadCodeText.Circular].Text + mPathText + cTexts[TDeadCodeText.LikeF2047].Text,
      mDetails,
      TRuleSeverity.Error, mFixes, mRelated);
  end
  else if FContext.Live then
  begin
    // Im Editor nur als Hinweis (#896), projektweit mit dem Schweregrad der Regel (#64).
    AddFinding(AReference.Range, cTexts[TDeadCodeText.Circular].Text + mPathText +
      cTexts[TDeadCodeText.ViaImplementation].Text,
      mDetails, TRuleSeverity.Hint, mFixes, mRelated);
  end
  else
  begin
    AddFinding(AReference.Range, cTexts[TDeadCodeText.Circular].Text + mPathText +
      cTexts[TDeadCodeText.ViaImplementation].Text,
      mDetails, TRuleSeverity.Default, mFixes, mRelated);
  end;
end;

procedure TUsesCycleCheck.CheckReference(const AReference: TUsesReference);
var
  mSteps: TArray<TRuleUsesStep>;
  mAllInterface: Boolean;
begin
  if (AReference.List <> TUsesListKind.UsesList) or SameText(CleanName(AReference.Name), FOwnName) then
  begin
    Exit;
  end;
  if Assigned(FContext.Cancelled) and FContext.Cancelled() then
  begin
    raise ERuleCheckCancelled.Create(cUsesCycleRuleId);
  end;
  mSteps := CycleSteps(AReference, mAllInterface);
  if mSteps <> nil then
  begin
    ReportCycle(AReference, mSteps, mAllInterface);
  end;
end;

procedure TUsesCycleCheck.Run;
var
  mReason: string;
  mReference: TUsesReference;
begin
  FOwnName := TUsesClauses.OwnName(FContext.Tree.Tokens);
  CheckSelfReferences;
  if (FContext.ProjectFiles = nil) or not FContext.ProjectFiles.Complete(mReason) then
  begin
    Exit;
  end;
  FWithImplementation := TRuleOptions.Bool(FContext.Options, 'implementation', True);
  // Im Editor (#896) erscheinen erlaubte Zyklen über implementation nur mit diagnostics.usesCycleImplementation.
  if FContext.Live then
  begin
    FWithImplementation := FWithImplementation and FContext.UsesCycleImplementation;
  end;
  for mReference in TUsesClauses.References(FContext.Tree.Tokens) do
  begin
    CheckReference(mReference);
  end;
end;

{ TUsesCycleRule }

function TUsesCycleRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUsesCycleRuleId, TRuleSeverity.Warning, cTexts[TDeadCodeText.CycleTitle].Text);
end;

function TUsesCycleRule.Applies(const AContext: TRuleContext): Boolean;
begin
  // diagnostics.usesCycleLive aus (#896): keine Meldung beim Tippen, die projektweite Prüfung bleibt. Die Regel
  // läuft dann nicht, ihr lsp-ignore ist also nicht unnötig (#1135).
  Result := not (AContext.Live and AContext.NoUsesCycleLive);
end;

procedure TUsesCycleRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRange: TTextRange;
  mCheck: TUsesCycleCheck;
begin
  if (AContext.Tree = nil) or (AContext.FileName = '') or IsProgramFile(AContext.FileName) or
    not UnitNameRange(AContext.Tree.Tokens, mRange) or not Applies(AContext) then
  begin
    Exit;
  end;
  mCheck := TUsesCycleCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnusedDeclarationCheck }

type
  /// <summary>Ein Lauf von unused-declaration über eine Datei.</summary>
  TUnusedDeclarationCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FLocal: TUnitIndex;
    FTokens: TArray<TPascalToken>;
    FLines: TArray<string>;
    FLineBreak: string;
    FConsidered: TConsideredUsed;
    // Namen (klein) mit einer Deklaration im interface-Teil: deren Rumpf im implementation-Teil ist kein Kandidat.
    FInterfaceNames: TDictionary<string, Boolean>;
    // Name (klein) -> Positionen aller Bezeichner dieses Namens.
    FOccurrences: TObjectDictionary<string, TList<TTextPosition>>;
    // Schlüssel (Name mit Parametertypen) schon geprüfter Kandidaten.
    FSeen: TDictionary<string, Boolean>;
    function Candidate(const ASymbol: TIndexSymbol): Boolean;
    function OwnRanges(const ASymbol: TIndexSymbol): TArray<TTextRange>;
    function Declarations(const AName: string): TArray<TTextPosition>;
    function Used(const ASymbol: TIndexSymbol): Boolean;
    function UsedAsAttribute(const ASymbol: TIndexSymbol): Boolean;
    function IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
    function FirstCandidate(const ASymbol: TIndexSymbol): Boolean;
    function Kept(const ASymbol: TIndexSymbol): Boolean;
    procedure CollectNames;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function KindText(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Routine:
      Result := cTexts[TDeadCodeText.Routine].Text;
    TIndexSymbolKind.Constant:
      Result := cTexts[TDeadCodeText.Constant].Text;
    TIndexSymbolKind.Variable:
      Result := cTexts[TDeadCodeText.GlobalVariable].Text;
  else
    Result := cTexts[TDeadCodeText.TypeWord].Text;
  end;
end;

/// <summary>Ist APosition eine der Positionen in APositions?</summary>
function AnySamePosition(const APosition: TTextPosition; const APositions: TArray<TTextPosition>): Boolean;
var
  mOther: TTextPosition;
begin
  Result := False;
  for mOther in APositions do
  begin
    Result := Result or SamePosition(mOther, APosition);
  end;
end;

constructor TUnusedDeclarationCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FLocal := TRuleDerived.UnitIndex(FCache, AContext);
  FTokens := TRuleDerived.CodeTokens(FCache, AContext);
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  if FLineBreak = '' then
  begin
    FLineBreak := sLineBreak;
  end;
  FInterfaceNames := TDictionary<string, Boolean>.Create;
  FOccurrences := TObjectDictionary<string, TList<TTextPosition>>.Create([doOwnsValues]);
  FSeen := TDictionary<string, Boolean>.Create;
  // Dienst „gilt als verwendet“ (#1102) mit deadCode.keepAttributes und deadCode.keepPatterns.
  FConsidered := TConsideredUsed.Create(AContext.Index, FLocal, FTokens, AContext.KeepAttributes,
    AContext.KeepPatterns);
end;

destructor TUnusedDeclarationCheck.Destroy;
begin
  FConsidered.Free;
  FSeen.Free;
  FOccurrences.Free;
  FInterfaceNames.Free;
  inherited Destroy;
end;

function TUnusedDeclarationCheck.Candidate(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Container = '') and not ASymbol.InInterface and not ASymbol.Unavailable and
    (ASymbol.FileName = '') and ((ASymbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Variable]) or IsTypeKind(ASymbol.Kind)) and
    not FInterfaceNames.ContainsKey(LowerCase(ASymbol.Name));
end;

/// <summary>Bereiche, deren Vorkommen von ASymbol keine Verwendung sind: eigene Rümpfe (Rekursion), bei Typen
/// die Deklaration und die Rümpfe der eigenen Methoden samt Kopf.</summary>
function TUnusedDeclarationCheck.OwnRanges(const ASymbol: TIndexSymbol): TArray<TTextRange>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  if IsTypeKind(ASymbol.Kind) then
  begin
    Result := [ASymbol.Range];
  end;
  for mNode in TRuleDerived.Routines(FCache, FContext) do
  begin
    if ((ASymbol.Kind = TIndexSymbolKind.Routine) and SameText(mNode.Name, ASymbol.Name)) or
      (IsTypeKind(ASymbol.Kind) and
      StartsText(ASymbol.Name + '.', TRoutineSignatures.WithoutTypeParams(mNode.Name))) then
    begin
      Result := Result + [TTextRange.Create(mNode.StartPos, mNode.EndPos)];
    end;
  end;
end;

/// <summary>Positionen der Deklarationen auf Unit-Ebene mit dem Namen (auch forward und Rümpfe).</summary>
function TUnusedDeclarationCheck.Declarations(const AName: string): TArray<TTextPosition>;
var
  mPosition: Integer;
begin
  Result := nil;
  for mPosition in FLocal.SymbolsNamed(AName) do
  begin
    if FLocal.Symbols[mPosition].Container = '' then
    begin
      Result := Result + [FLocal.Symbols[mPosition].SelectionRange.StartPos];
    end;
  end;
end;

function TUnusedDeclarationCheck.Used(const ASymbol: TIndexSymbol): Boolean;
var
  mPositions: TList<TTextPosition>;
  mPosition: TTextPosition;
  mDeclared: TArray<TTextPosition>;
  mOwn: TArray<TTextRange>;
begin
  Result := False;
  if FOccurrences.TryGetValue(LowerCase(ASymbol.Name), mPositions) then
  begin
    mDeclared := Declarations(ASymbol.Name);
    mOwn := OwnRanges(ASymbol);
    for mPosition in mPositions do
    begin
      if not Inside(mPosition, mOwn) and not AnySamePosition(mPosition, mDeclared) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>[Behalten] verwendet BehaltenAttribute.</summary>
function TUnusedDeclarationCheck.UsedAsAttribute(const ASymbol: TIndexSymbol): Boolean;
var
  mShort: string;
  mPositions: TList<TTextPosition>;
  mPosition: TTextPosition;
begin
  Result := False;
  if (ASymbol.Kind <> TIndexSymbolKind.ClassType) or not EndsText('Attribute', ASymbol.Name) or
    (Length(ASymbol.Name) = Length('Attribute')) then
  begin
    Exit;
  end;
  mShort := Copy(ASymbol.Name, 1, Length(ASymbol.Name) - Length('Attribute'));
  if FOccurrences.TryGetValue(LowerCase(mShort), mPositions) then
  begin
    for mPosition in mPositions do
    begin
      if not Inside(mPosition, [ASymbol.Range]) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TUnusedDeclarationCheck.IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
var
  mLine: Integer;
  mIndent: string;
begin
  mLine := ASymbol.Range.StartPos.Line;
  mIndent := '';
  if mLine < Length(FLines) then
  begin
    mIndent := Copy(FLines[mLine], 1, Length(FLines[mLine]) - Length(TrimLeft(FLines[mLine])));
  end;
  Result := TRuleFix.Create(cTexts[TDeadCodeText.MarkIntended].Text,
    [TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), mIndent + '// lsp-ignore: ' +
    cUnusedDeclarationRuleId + FLineBreak)]);
  Result.Alternative := True;
end;

/// <summary>Erster Kandidat seines Schlüssels? Forward-Deklaration und Rumpf sind ein Kandidat; Überladungen
/// einzeln.</summary>
function TUnusedDeclarationCheck.FirstCandidate(const ASymbol: TIndexSymbol): Boolean;
var
  mKey: string;
begin
  Result := Candidate(ASymbol);
  if Result then
  begin
    mKey := LowerCase(ASymbol.Name + '(' + string.Join(',', ASymbol.ParamTypes) + ')');
    Result := not FSeen.ContainsKey(mKey);
    FSeen.AddOrSetValue(mKey, True);
  end;
end;

/// <summary>Verwendet, als verwendet geltend oder aus der Formulardatei (Komponenten, Ereignisse,
/// Klassen)?</summary>
function TUnusedDeclarationCheck.Kept(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := Used(ASymbol) or UsedAsAttribute(ASymbol) or
    (FConsidered.Reason(ASymbol) <> TConsideredUsedReason.None) or
    (FContext.FormText <> '') and ContainsText(FContext.FormText, ASymbol.Name);
end;

procedure TUnusedDeclarationCheck.CollectNames;
var
  mSymbol: TIndexSymbol;
  mToken: TPascalToken;
  mName: string;
  mList: TList<TTextPosition>;
begin
  for mSymbol in FLocal.Symbols do
  begin
    if (mSymbol.Container = '') and mSymbol.InInterface then
    begin
      FInterfaceNames.AddOrSetValue(LowerCase(mSymbol.Name), True);
    end;
  end;
  for mToken in FTokens do
  begin
    if mToken.Kind = TPascalTokenKind.Identifier then
    begin
      mName := LowerCase(CleanName(mToken.Text));
      if not FOccurrences.TryGetValue(mName, mList) then
      begin
        mList := TList<TTextPosition>.Create;
        FOccurrences.Add(mName, mList);
      end;
      mList.Add(mToken.StartPos);
    end;
  end;
end;

procedure TUnusedDeclarationCheck.Run;
var
  mSymbol: TIndexSymbol;
begin
  CollectNames;
  for mSymbol in FLocal.Symbols do
  begin
    if FirstCandidate(mSymbol) and not Kept(mSymbol) then
    begin
      FReport.Add(mSymbol.SelectionRange, cTexts[TDeadCodeText.NeverUsed].Fmt([KindText(mSymbol),
        mSymbol.Name]), TRuleConfidence.High, [IgnoreFix(mSymbol)]);
    end;
  end;
end;

{ TUnusedDeclarationRule }

function TUnusedDeclarationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUnusedDeclarationRuleId, TRuleSeverity.Hint,
    cTexts[TDeadCodeText.UnusedTitle].Text);
end;

procedure TUnusedDeclarationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnusedDeclarationCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or HasIncludes(AContext.Tree) then
  begin
    Exit;
  end;
  mCheck := TUnusedDeclarationCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnusedUnitRule }

/// <summary>Datei, die unused-unit prüft: eine Unit (.pas) mit Projekten, die alle zu den Arten aus
/// projectKinds gehören. ARange ist der Unit-Name im Kopf.</summary>
function UnusedUnitChecked(const AContext: TRuleContext; out ARange: TTextRange): Boolean;
var
  mProjectKinds: TArray<string>;
  mProjects: TArray<TRuleProject>;
  mProject: TRuleProject;
begin
  Result := (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) and (AContext.ProjectFiles <> nil) and
    SameText(ExtractFileExt(AContext.FileName), '.pas') and UnitNameRange(AContext.Tree.Tokens, ARange);
  if Result then
  begin
    mProjectKinds := TRuleOptions.Strings(AContext.Options, 'projectKinds', ['application']);
    mProjects := AContext.ProjectFiles.ProjectsOf(AContext.FileName, False);
    Result := mProjects <> nil;
    for mProject in mProjects do
    begin
      Result := Result and (IndexText(ProjectKindKey(mProject.Kind), mProjectKinds) >= 0);
    end;
  end;
end;

/// <summary>Nur Programme verwenden die Unit: ihre Dateinamen in APrograms; False, sobald eine Unit sie
/// verwendet.</summary>
function OnlyPrograms(const AUsers: TArray<TRuleUsesStep>; out APrograms: string): Boolean;
var
  mUser: TRuleUsesStep;
begin
  Result := True;
  APrograms := '';
  for mUser in AUsers do
  begin
    Result := Result and IsProgramFile(mUser.FileName);
    if APrograms <> '' then
    begin
      APrograms := APrograms + ', ';
    end;
    APrograms := APrograms + ExtractFileName(mUser.FileName);
  end;
end;

/// <summary>Verwendet das Programm AFile außerhalb seiner uses-Liste einen Bezeichner aus ANames? Nicht lesbar
/// zählt als ja.</summary>
function ProgramUses(const AContext: TRuleContext; const AFile: string;
  const ANames: TDictionary<string, Boolean>): Boolean;
var
  mText: string;
  mTree: TSyntaxTree;
  mToken: TPascalToken;
  mClauses: TArray<TTextRange>;
  mReference: TUsesReference;
begin
  if not AContext.ProjectFiles.ReadText(AFile, mText) then
  begin
    Exit(True);
  end;
  Result := False;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mClauses := nil;
    for mReference in TUsesClauses.References(mTree.Tokens) do
    begin
      mClauses := mClauses + [mReference.Range];
    end;
    for mToken in mTree.Tokens do
    begin
      Result := Result or (mToken.Kind = TPascalTokenKind.Identifier) and
        ANames.ContainsKey(LowerCase(CleanName(mToken.Text))) and not Inside(mToken.StartPos, mClauses);
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Verwendet eines der Programme in AUsers einen Bezeichner aus dem interface-Teil von ALocal?</summary>
function AnyProgramUses(const AContext: TRuleContext; const AUsers: TArray<TRuleUsesStep>;
  const ALocal: TUnitIndex): Boolean;
var
  mNames: TDictionary<string, Boolean>;
  mSymbol: TIndexSymbol;
  mUser: TRuleUsesStep;
begin
  Result := False;
  mNames := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in ALocal.Symbols do
    begin
      if (mSymbol.Container = '') and mSymbol.InInterface then
      begin
        mNames.AddOrSetValue(LowerCase(mSymbol.Name), True);
      end;
    end;
    for mUser in AUsers do
    begin
      Result := Result or ProgramUses(AContext, mUser.FileName, mNames);
    end;
  finally
    mNames.Free;
  end;
end;

function TUnusedUnitRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUnusedUnitRuleId, TRuleSeverity.Hint,
    cTexts[TDeadCodeText.UnitTitle].Text);
end;

procedure TUnusedUnitRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mReason, mPrograms, mOwnName: string;
  mUsers: TArray<TRuleUsesStep>;
  mLocal: TUnitIndex;
  mRange: TTextRange;
begin
  if not UnusedUnitChecked(AContext, mRange) or not AContext.ProjectFiles.Complete(mReason) or
    not AContext.ProjectFiles.UsedBy(AContext.FileName, mUsers) then
  begin
    Exit;
  end;
  mLocal := TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext);
  // Registrierungen und andere Seiteneffekte beim Start; Testklassen findet der Testrunner über ihre Attribute.
  if mLocal.HasInitialization or HasTestFixture(AContext.Tree.Tokens) or not OnlyPrograms(mUsers, mPrograms) or
    AnyProgramUses(AContext, mUsers, mLocal) then
  begin
    Exit;
  end;
  mOwnName := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if mPrograms = '' then
  begin
    AReport.Add(mRange, cTexts[TDeadCodeText.UnitUnused].Fmt([mOwnName]),
      TRuleConfidence.Medium);
  end
  else
  begin
    AReport.Add(mRange, cTexts[TDeadCodeText.UnitOnlyBy].Fmt([mOwnName, mPrograms]), TRuleConfidence.Medium);
  end;
end;

/// <summary>Wann unused-uses und uses-only-in-implementation prüfen.</summary>
function UsesEntriesChecked(const AContext: TRuleContext): Boolean;
begin
  // Im Editor zeigt der Server dieselben Einträge (#621); ohne Index ist nichts sicher, und bei Syntaxfehlern
  // fehlen Bezeichner. Das uses eines Programms, einer Bibliothek oder eines Packages zählt die Units des
  // Projekts auf (Formulare, "in"-Pfade, DCCReference): Ein Eintrag dort ist Mitgliedschaft, nicht Abhängigkeit.
  Result := not AContext.Live and (AContext.Index <> nil) and (AContext.Tree <> nil) and
    (Length(AContext.Tree.Diagnostics) = 0) and
    (TModuleHeader.Read(AContext.Tree.Tokens).Kind = TModuleKind.UnitModule);
end;

{ TUnusedUsesRule }

function TUnusedUsesRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUnusedUsesRuleId, TRuleSeverity.Hint, cTexts[TDeadCodeText.UsesTitle].Text);
end;

class function TUnusedUsesRule.Keep(const AOptions: string; const AUsesKeep: TArray<string>): TArray<string>;
begin
  Result := AUsesKeep + TRuleOptions.Strings(AOptions, 'keep', nil);
end;

function TUnusedUsesRule.Applies(const AContext: TRuleContext): Boolean;
begin
  Result := UsesEntriesChecked(AContext);
end;

/// <summary>Auffällige uses-Einträge der Datei wie im Editor (#621) samt Namensauflösung (#1925); AKeep: Units,
/// die nie als ungenutzt gelten.</summary>
function UsesEntries(const AContext: TRuleContext; const AKeep: TArray<string>): TArray<TUsesEntry>;
var
  mInfo: TUsesUnitInfoFunc;
  mSource: TUsesUsageSource;
begin
  // Module, auf die die Formulardatei verweist: Ihr uses-Eintrag ist gebraucht (dfm-reference-unit-missing).
  mInfo := TUsesUsage.UnitInfo(AContext.Index, AContext.EnsureUnit, TFormModel.ForeignModulesOf(AContext.FormText));
  mSource := Default(TUsesUsageSource);
  mSource.Index := AContext.Index;
  mSource.EnsureUnit := AContext.EnsureUnit;
  mSource.TreeUnits := AContext.TreeUnits;
  mSource.NameFacts := AContext.NameFacts;
  mSource.Namespaces := AContext.Namespaces;
  Result := TUsesActions.Entries(AContext.Tree.Tokens, AContext.InactiveRanges, mInfo, AKeep,
    TUsesUsage.Resolve(mSource, AContext.Tree, AContext.RelativePath, AContext.InactiveRanges, mInfo));
end;

procedure TUnusedUsesRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEntry: TUsesEntry;
  mEdit: TTextEdit;
  mFixes: TArray<TRuleFix>;
begin
  // Auch bei einem Aufruf ohne Prüflauf (der Lauf fragt Applies vorher).
  if not Applies(AContext) then
  begin
    Exit;
  end;
  for mEntry in UsesEntries(AContext, Keep(AContext.Options, AContext.UsesKeep)) do
  begin
    if mEntry.State <> TUsesEntryState.Unused then
    begin
      Continue;
    end;
    mFixes := nil;
    if TUsesActions.RemoveEntries(AContext.Text, TArray<TTextRange>.Create(mEntry.Range), mEdit) then
    begin
      mFixes := TArray<TRuleFix>.Create(TRuleFix.Create(cTexts[TDeadCodeText.RemoveEntry].Text,
        TArray<TTextEdit>.Create(mEdit), True));
    end;
    AReport.Add(mEntry.Range, cTexts[TDeadCodeText.NothingUsed].Fmt([mEntry.Name]), TRuleConfidence.High, mFixes);
  end;
end;

{ TUsesOnlyInImplementationRule }

function TUsesOnlyInImplementationRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cUsesOnlyInImplementationRuleId, TRuleSeverity.Hint,
    cTexts[TDeadCodeText.PlacementTitle].Text);
end;

function TUsesOnlyInImplementationRule.Applies(const AContext: TRuleContext): Boolean;
begin
  Result := UsesEntriesChecked(AContext);
end;

procedure TUsesOnlyInImplementationRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEntry: TUsesEntry;
begin
  if not Applies(AContext) then
  begin
    Exit;
  end;
  // usesKeep betrifft nur ungenutzte Einträge. Units mit initialization nennt Entries hier nicht: Im
  // implementation-uses liefe ihre Initialisierung später.
  for mEntry in UsesEntries(AContext, AContext.UsesKeep) do
  begin
    if mEntry.State = TUsesEntryState.OnlyImplementation then
    begin
      AReport.Add(mEntry.Range, cTexts[TDeadCodeText.OnlyImplementation].Fmt([mEntry.Name]), TRuleConfidence.High,
        MoveToImplementationFixes(AContext, mEntry.Name));
    end;
  end;
end;

procedure RegisterDeadCodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUsesCycleRule.Create);
  ARegistry.Register(TUnusedDeclarationRule.Create);
  ARegistry.Register(TUnusedUnitRule.Create);
  ARegistry.Register(TUnusedUsesRule.Create);
  ARegistry.Register(TUsesOnlyInImplementationRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DeadCode', cTexts);

end.
