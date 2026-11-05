unit Atlas.Common.Rules.Builtin.PublicMembers;

// Regel unused-public-member (#1102, Gruppe „Stil und Metriken“): eine
// public- oder published-Methode, -Konstante oder -Property (auf Wunsch auch
// protected und Felder) bzw. eine Routine, Konstante, ein Typ oder eine
// globale Variable aus dem interface-Teil (Option unitKinds, Typen und
// Variablen seit #64), die in der ganzen Projektgruppe nirgends verwendet
// wird. Erweitert unused-private-member (#1020) über die Grenze der Unit.
//
// Bei Typen zählen Vorkommen in der eigenen Deklaration und in den Rümpfen
// der eigenen Methoden (samt Methodenkopf TTyp.Name) nicht; ein Typ, den eine
// Datei des Suchbereichs registriert (RegisterComponents …), gilt als
// verwendet. Für Attributklassen (XyzAttribute) zählt auch die Kurzform [Xyz].
// Zu keepAttributes und keepPatterns kommen deadCode.keepAttributes und
// deadCode.keepPatterns aus den Einstellungen (#64).
//
// Ablauf je Kandidat:
// - Ausnahmen über den Dienst „gilt als verwendet“ (Rules.ConsideredUsed).
// - Dateien im Suchbereich (Projekt bzw. Projektgruppe, IRuleProjectFiles):
//   Nur Dateien, in denen der Name als Bezeichner vorkommt (Verwendungen im
//   Index, #492), werden geparst; jedes Vorkommen außer Deklarationen und dem
//   eigenen Rumpf wird über die Namensauflösung geprüft. Löst es nicht sicher
//   auf, zählt es als Verwendung.
// - Formulardateien (Ereignis-Handler, Properties) und, mit
//   stringLiteralsCountAsUse, String-Literale mit genau dem Namen (RTTI).
// - published-Mitglieder gelten als verwendet, solange eine Formulardatei des
//   Suchbereichs nicht lesbar ist, und für Klassen, die eine Datei des
//   Suchbereichs in RegisterComponents, RegisterClass oder RegisterClasses
//   nennt (Streaming und Objektinspektor erreichen sie über RTTI).
// - Verwendungen nur in Testprojekten zählen mit testsCountAsUse = false nicht;
//   die Meldung nennt dann das Testprojekt.
//
// Die Regel schweigt, solange die Projekte nicht vollständig indiziert sind,
// eine Datei mit dem Namen nicht lesbar ist, die Unit Include-Dateien einbindet
// oder ein Projekt der Unit eine Art hat, die nicht in projectKinds steht
// (Vorgabe: nur Anwendungen; Packages und DLLs haben Nutzer außerhalb der
// Gruppe).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnusedPublicMemberRuleId = 'unused-public-member';

type
  TUnusedPublicMemberRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPublicMemberRules(const ARegistry: TRuleRegistry);

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
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.ConsideredUsed,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPublicMembersText = (GlobalVariable, PublicType, Searched, FileOne, FileMany, AndSep, FormOne, FormMany, OfGroup,
    OfProject, MarkPublic, NeverUsed, OnlyUsedIn, Title, FieldNoun, ConstantNoun, PropertyNoun, ClassVariableNoun,
    RoutineNoun, MethodNoun, PublishedKind, ProtectedNeuter, ProtectedKind, PublicNeuter, PublicKind);

const
  cTexts: array[TPublicMembersText] of TAtlasText = (
    (De: 'Globale Variable'; En: 'Global variable'),
    (De: 'Öffentlicher Typ'; En: 'Public type'),
    (De: 'Durchsucht: '; En: 'Searched: '),
    (De: 'Datei'; En: 'file'),
    (De: 'Dateien'; En: 'files'),
    (De: ' und '; En: ' and '),
    (De: 'Formular'; En: 'form'),
    (De: 'Formulare'; En: 'forms'),
    (De: ' der Projektgruppe'; En: ' of the project group'),
    (De: ' des Projekts'; En: ' of the project'),
    (De: 'Als bewusst öffentlich markieren (lsp-ignore)'; En: 'Mark as intentionally public (lsp-ignore)'),
    (De: '%s %s wird im Projekt nirgends verwendet.'; En: '%s %s is not used anywhere in the project.'),
    (De: '%s %s wird nur in %s verwendet.'; En: '%s %s is only used in %s.'),
    (De: 'Öffentliches Mitglied wird im Projekt nie verwendet'; En: 'Public member is never used in the project'),
    (De: 'Feld'; En: 'field'),
    (De: 'Konstante'; En: 'constant'),
    (De: 'Property'; En: 'property'),
    (De: 'Klassenvariable'; En: 'class variable'),
    (De: 'Routine'; En: 'routine'),
    (De: 'Methode'; En: 'method'),
    (De: 'Published-%s'; En: 'Published %s'),
    (De: 'Geschütztes %s'; En: 'Protected %s'),
    (De: 'Geschützte %s'; En: 'Protected %s'),
    (De: 'Öffentliches %s'; En: 'Public %s'),
    (De: 'Öffentliche %s'; En: 'Public %s'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Aufrufe, die Klassen für Streaming und Objektinspektor bekannt machen.</summary>
  RegisterCalls: array[0..2] of string = ('RegisterComponents', 'RegisterClass', 'RegisterClasses');

type
{$SCOPEDENUMS ON}
  TUsage = (Used, Unused, OnlyTests);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Datei im Suchbereich.</summary>
  TSearchFile = record
    FileName: string;
    /// <summary>Gehört nur zu Testprojekten.</summary>
    OnlyTests: Boolean;
    /// <summary>Name des ersten Testprojekts für die Meldung.</summary>
    TestProject: string;
  end;

/// <summary>"Öffentliche Methode", "Published-Property", "Geschütztes Feld" …</summary>
function KindText(const ASymbol: TIndexSymbol): string;
var
  Noun: string;
  Neuter: Boolean;
begin
  // Unit-Ebene (#64): Typen und globale Variablen.
  if ASymbol.Container = '' then
    case ASymbol.Kind of
      TIndexSymbolKind.Variable:
        Exit(cTexts[TPublicMembersText.GlobalVariable].Text);
      TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias:
        Exit(cTexts[TPublicMembersText.PublicType].Text);
    else
      // Übrige Arten: nichts zu tun.
    end;
  Neuter := ASymbol.Kind = TIndexSymbolKind.Field;
  case ASymbol.Kind of
    TIndexSymbolKind.Field:
      Noun := cTexts[TPublicMembersText.FieldNoun].Text;
    TIndexSymbolKind.Constant:
      Noun := cTexts[TPublicMembersText.ConstantNoun].Text;
    TIndexSymbolKind.Property_:
      Noun := cTexts[TPublicMembersText.PropertyNoun].Text;
    TIndexSymbolKind.Variable:
      Noun := cTexts[TPublicMembersText.ClassVariableNoun].Text;
    TIndexSymbolKind.Routine:
      Noun := cTexts[TPublicMembersText.RoutineNoun].Text;
  else
    Noun := cTexts[TPublicMembersText.MethodNoun].Text;
  end;
  // Das Geschlecht des Nomens zählt nur im Deutschen; die englischen Texte sind gleich.
  case ASymbol.Visibility of
    TIndexVisibility.Published:
      Result := cTexts[TPublicMembersText.PublishedKind].Fmt([Noun]);
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      if Neuter then
      begin
        Result := cTexts[TPublicMembersText.ProtectedNeuter].Fmt([Noun]);
      end
      else
      begin
        Result := cTexts[TPublicMembersText.ProtectedKind].Fmt([Noun]);
      end;
  else
    if Neuter then
    begin
      Result := cTexts[TPublicMembersText.PublicNeuter].Fmt([Noun]);
    end
    else
    begin
      Result := cTexts[TPublicMembersText.PublicKind].Fmt([Noun]);
    end;
  end;
end;

function VisibilityKey(AVisibility: TIndexVisibility): string;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 'published';
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      Result := 'protected';
    TIndexVisibility.Public:
      Result := 'public';
  else
    Result := '';
  end;
end;

function MemberKindKey(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Method, TIndexSymbolKind.Routine:
      Result := 'method';
    TIndexSymbolKind.Constant:
      Result := 'constant';
    TIndexSymbolKind.Property_:
      Result := 'property';
    TIndexSymbolKind.Field:
      Result := 'field';
    TIndexSymbolKind.Variable:
      Result := 'classVar';
  else
    Result := '';
  end;
end;

/// <summary>Kennung für die Option unitKinds (#64); '' für Arten, die die Regel auf Unit-Ebene nicht prüft
/// (Helfer werden über den erweiterten Typ verwendet).</summary>
function UnitKindKey(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Routine:
      Result := 'routine';
    TIndexSymbolKind.Constant:
      Result := 'constant';
    TIndexSymbolKind.Variable:
      Result := 'variable';
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias:
      Result := 'type';
  else
    Result := '';
  end;
end;

function IsTypeSymbol(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Container = '') and (UnitKindKey(ASymbol) = 'type');
end;

/// <summary>Name ohne Typparameter: TListe&lt;T&gt;.Add -> TListe.Add.</summary>
function WithoutTypeParams(const AName: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(AName) do
  begin
    if AName[Index] = '<' then
    begin
      Inc(Depth);
    end
    else if AName[Index] = '>' then
    begin
      Dec(Depth);
    end
    else if Depth = 0 then
    begin
      Result := Result + AName[Index];
    end;
  end;
end;

/// <summary>Kurzform einer Attributklasse ([Behalten] für BehaltenAttribute), sonst ''.</summary>
function AttributeShortName(const ASymbol: TIndexSymbol): string;
begin
  Result := '';
  if (ASymbol.Kind = TIndexSymbolKind.ClassType) and (Length(ASymbol.Name) > Length('Attribute')) and
    EndsText('Attribute', ASymbol.Name) then
  begin
    Result := Copy(ASymbol.Name, 1, Length(ASymbol.Name) - Length('Attribute'));
  end;
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

function QualifiedOf(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + '.' + ASymbol.Name;
  end
  else
  begin
    Result := ASymbol.Name;
  end;
end;

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

function Contains(const AItems: TArray<string>; const AItem: string): Boolean;
begin
  Result := IndexText(AItem, AItems) >= 0;
end;

/// <summary>Liegt A an oder hinter B?</summary>
function NotBefore(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line > B.Line) or ((A.Line = B.Line) and (A.Character >= B.Character));
end;

/// <summary>Liegt APosition in einem der Bereiche ARanges (beide Enden eingeschlossen)?</summary>
function InsideAny(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
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

/// <summary>Bindet die Unit mit {$I …} bzw. {$INCLUDE …} Dateien ein?</summary>
function HasIncludes(const ATokens: TArray<TPascalToken>): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  for mToken in ATokens do
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

/// <summary>Steht bei AIndex ein Aufruf RegisterComponents, RegisterClass oder RegisterClasses mit Klammer?</summary>
function IsRegisterCall(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (IndexText(CleanName(ATokens[AIndex].Text), RegisterCalls) >= 0) and ATokens[AIndex + 1].IsSymbol('(');
end;

/// <summary>Nennen die Argumente ab der öffnenden Klammer bei AOpen bis zur schließenden die Klasse AClass?
/// RegisterComponents('Seite', [TA, TB]), RegisterClass(TA).</summary>
function ArgumentsName(const ATokens: TArray<TPascalToken>; AOpen: Integer; const AClass: string): Boolean;
var
  mAt, mDepth: Integer;
begin
  Result := False;
  mDepth := 0;
  mAt := AOpen;
  while not Result and (mAt <= High(ATokens)) do
  begin
    if ATokens[mAt].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mAt].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end
    else
    begin
      Result := (ATokens[mAt].Kind = TPascalTokenKind.Identifier) and SameText(CleanName(ATokens[mAt].Text), AClass);
    end;
    Inc(mAt);
  end;
end;

/// <summary>Nennt ein Aufruf RegisterComponents, RegisterClass oder RegisterClasses in ATokens die Klasse
/// AClass?</summary>
function RegistersIn(const ATokens: TArray<TPascalToken>; const AClass: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    if IsRegisterCall(ATokens, mIndex) and ArgumentsName(ATokens, mIndex + 1, AClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Steht das String-Literal ALiteral (samt Hochkommas) in ATokens?</summary>
function LiteralIn(const ATokens: TArray<TPascalToken>; const ALiteral: string): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.StringLiteral) and SameText(mToken.Text, ALiteral) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>"1 Datei" bzw. "12 Dateien".</summary>
function Counted(ACount: Integer; const AOne, AMany: string): string;
begin
  if ACount = 1 then
  begin
    Result := '1 ' + AOne;
  end
  else
  begin
    Result := Format('%d %s', [ACount, AMany]);
  end;
end;

/// <summary>Erste Deklaration von ASymbol (im Typ bzw. im interface-Teil)? Merkt sie in ASeen.</summary>
function FirstDeclaration(const ASymbol: TIndexSymbol; ASeen: TDictionary<string, Boolean>): Boolean;
var
  mKey: string;
begin
  if ASymbol.Unavailable or (ASymbol.FileName <> '') then
  begin
    Exit(False);
  end;
  // Nur die erste Deklaration entscheidet, nicht der Rumpf; Überladungen einzeln. Auch eine nicht gewünschte
  // Deklaration (protected) zählt als gesehen, sonst prüfte die Regel den Rumpf, der im Index als public steht.
  mKey := LowerCase(ASymbol.Container + '.' + ASymbol.Name + '(' + string.Join(',', ASymbol.ParamTypes) + ')');
  Result := not ASeen.ContainsKey(mKey);
  if Result then
  begin
    ASeen.Add(mKey, True);
  end;
end;

type
  /// <summary>Optionen der Regel.</summary>
  TPublicMemberOptions = record
    Visibilities, MemberKinds, ProjectKinds, UnitKinds: TArray<string>;
    UnitLevel, WholeGroup, TestsCount, StringsCount: Boolean;
    class function Read(const AOptions: string): TPublicMemberOptions; static;
    /// <summary>Gehören alle Projekte von AFileName zu einer erlaubten Art?</summary>
    function KindsAllowed(const AProjects: TArray<TRuleProject>; const AFileName: string): Boolean;
    /// <summary>Prüft die Regel ASymbol nach Art und Sichtbarkeit?</summary>
    function Wanted(const ASymbol: TIndexSymbol): Boolean;
  end;

  /// <summary>Welche Vorkommen eines Namens in einer Datei keine Verwendung sind.</summary>
  TOccurrenceFilter = record
    /// <summary>Deklarationen mit dem Namen.</summary>
    Declared: TArray<TTextPosition>;
    /// <summary>Eigene Rümpfe bzw. die eigene Typdeklaration.</summary>
    Bodies: TArray<TTextRange>;
    function Excludes(const APosition: TTextPosition): Boolean;
  end;

  /// <summary>Dateien und Formulare im Suchbereich samt gelesenen Texten.</summary>
  TSearchArea = class
  private
    FContext: TRuleContext;
    FFiles: TList<TSearchFile>;
    FForms: TList<string>;
    FTexts: TDictionary<string, string>;
    // Klassen (Kurzname, klein) -> in RegisterComponents/RegisterClass(es) genannt; je Prüfung einmal.
    FRegistered: TDictionary<string, Boolean>;
    // 0 = noch nicht geprüft, 1 = alle Formulardateien lesbar, 2 = mindestens eine nicht.
    FFormsState: Integer;
    procedure AddSource(ASeen: TDictionary<string, Integer>; const AProject: TRuleProject; const ASource: string);
    procedure AddForms(const AProject: TRuleProject);
    /// <summary>Nennt AFile einen der Registrieraufrufe? AUnknown: für einen ist es nicht sicher.</summary>
    function MentionsRegisterCall(const AFile: string; out AUnknown: Boolean): Boolean;
    function FileRegisters(const AEntry: TSearchFile; const AShort: string): Boolean;
    function LiteralInFile(const AFile, AText, ALiteral: string): Boolean;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    procedure Collect(const AProjects: TArray<TRuleProject>);
    function IsOwnFile(const AFile: string): Boolean;
    function TextOf(const AFile: string; out AText: string): Boolean;
    function InForms(const AName: string): Boolean;
    /// <summary>Ist eine Formulardatei des Suchbereichs nicht lesbar? Dann können published-Methoden dort als
    /// Handler stehen.</summary>
    function FormUnreadable: Boolean;
    /// <summary>Registriert eine Datei des Suchbereichs die Klasse AContainer (RegisterComponents,
    /// RegisterClass, RegisterClasses)? Nicht lesbare Dateien mit einem dieser Aufrufe zählen als ja.</summary>
    function IsRegistered(const AContainer: string): Boolean;
    /// <summary>Kommt AName als String-Literal ('Name') in einer Datei des Suchbereichs vor?</summary>
    function InStrings(const AName: string): Boolean;
    /// <summary>Durchsuchter Bereich für den Befund-Hover: "Durchsucht: 214 Units und 37 Formulare der
    /// Projektgruppe".</summary>
    function SearchedText(AWholeGroup: Boolean): string;
    property Files: TList<TSearchFile> read FFiles;
  end;

  /// <summary>Ein Lauf von unused-public-member über eine Datei.</summary>
  TPublicMemberScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FOptions: TPublicMemberOptions;
    FCache: IRuleDerivedCache;
    FLocal: TUnitIndex;
    FLines: TArray<string>;
    FLineBreak: string;
    FResolver: TNameResolver;
    FConsidered: TConsideredUsed;
    FArea: TSearchArea;
    function IsTarget(const AResolved: TResolvedSymbol; const ASymbol: TIndexSymbol; AAmbiguous: Boolean): Boolean;
    /// <summary>Deklarationen mit dem Namen in AFile: dort ist der Name keine Verwendung.</summary>
    function DeclaredAt(const AFile, AName: string): TArray<TTextPosition>;
    /// <summary>Bereiche von ASymbol in der eigenen Datei, deren Vorkommen keine Verwendung sind: die Rümpfe der
    /// Routine (Rekursion), bei Typen die Deklaration und die Rümpfe ihrer Methoden samt Kopf (#64).</summary>
    function OwnRanges(const ASymbol: TIndexSymbol): TArray<TTextRange>;
    /// <summary>Löst das Vorkommen bei APosition auf ASymbol auf? Nicht sicher auflösbar zählt als ja.</summary>
    function ResolvesTo(ATree: TSyntaxTree; const AFile: string; const APosition: TTextPosition;
      const ASymbol: TIndexSymbol): Boolean;
    function TokenUses(ATree: TSyntaxTree; const AFile: string; const ASymbol: TIndexSymbol;
      const AToken: TPascalToken; const AFilter: TOccurrenceFilter; const AShort: string): Boolean;
    /// <summary>Verwendet ATree (Datei AFile) ASymbol? Nicht sicher auflösbare Vorkommen zählen als Verwendung.
    /// </summary>
    function UsedInTree(ATree: TSyntaxTree; const AFile: string; const ASymbol: TIndexSymbol): Boolean;
    /// <summary>Kommt der Name von ASymbol (bei Attributklassen auch die Kurzform) in AFile vor?</summary>
    function NameInFile(const AFile: string; const ASymbol: TIndexSymbol): TRuleNameAnswer;
    /// <summary>Verwendet AFile ASymbol (AUsed)? False, wenn das nicht sicher zu beantworten ist.</summary>
    function UsedIn(const AFile: string; const ASymbol: TIndexSymbol; out AUsed: Boolean): Boolean;
    /// <summary>Used: verwendet oder nicht sicher; OnlyTests: verwendet, zählt aber nicht; sonst Unused.</summary>
    function FileUsage(const AEntry: TSearchFile; const ASymbol: TIndexSymbol): TUsage;
    /// <summary>Wo wird ASymbol verwendet? ATestProject: das Testprojekt bei OnlyTests. Was nicht sicher zu
    /// beantworten ist, gilt als Used.</summary>
    function UsageOf(const ASymbol: TIndexSymbol; out ATestProject: string): TUsage;
    function IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
    /// <summary>Gilt ASymbol ohne Suche als verwendet (Ausnahmen, Streaming über RTTI)?</summary>
    function IsExempt(const ASymbol: TIndexSymbol): Boolean;
    procedure CheckSymbol(const ASymbol: TIndexSymbol);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport;
      const AOptions: TPublicMemberOptions);
    destructor Destroy; override;
    procedure Run(const AProjects: TArray<TRuleProject>);
  end;

{ TPublicMemberOptions }

class function TPublicMemberOptions.Read(const AOptions: string): TPublicMemberOptions;
begin
  Result.Visibilities := TRuleOptions.Strings(AOptions, 'visibilities', ['public', 'published']);
  Result.MemberKinds := TRuleOptions.Strings(AOptions, 'memberKinds', ['method', 'constant', 'property']);
  Result.ProjectKinds := TRuleOptions.Strings(AOptions, 'projectKinds', ['application']);
  Result.UnitLevel := TRuleOptions.Bool(AOptions, 'unitLevel', True);
  Result.UnitKinds := TRuleOptions.Strings(AOptions, 'unitKinds', ['routine', 'constant', 'type', 'variable']);
  Result.WholeGroup := not SameText(TRuleOptions.Text(AOptions, 'scope', 'projectGroup'), 'project');
  Result.TestsCount := TRuleOptions.Bool(AOptions, 'testsCountAsUse', True);
  Result.StringsCount := TRuleOptions.Bool(AOptions, 'stringLiteralsCountAsUse', True);
end;

function TPublicMemberOptions.KindsAllowed(const AProjects: TArray<TRuleProject>; const AFileName: string): Boolean;
var
  mProject: TRuleProject;
  mSource: string;
begin
  for mProject in AProjects do
  begin
    for mSource in mProject.Sources do
    begin
      if SameText(mSource, AFileName) and not Contains(ProjectKinds, ProjectKindKey(mProject.Kind)) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

function TPublicMemberOptions.Wanted(const ASymbol: TIndexSymbol): Boolean;
begin
  if ASymbol.Unavailable or (ASymbol.FileName <> '') then
  begin
    Exit(False);
  end;
  // Unit-Ebene: Arten aus unitKinds (#64), unabhängig von memberKinds.
  if ASymbol.Container = '' then
  begin
    Exit(UnitLevel and ASymbol.InInterface and (UnitKindKey(ASymbol) <> '') and
      Contains(UnitKinds, UnitKindKey(ASymbol)));
  end;
  Result := Contains(MemberKinds, MemberKindKey(ASymbol)) and (ASymbol.Kind in [TIndexSymbolKind.Method,
    TIndexSymbolKind.Constant, TIndexSymbolKind.Property_, TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and
    Contains(Visibilities, VisibilityKey(ASymbol.Visibility));
end;

{ TOccurrenceFilter }

function TOccurrenceFilter.Excludes(const APosition: TTextPosition): Boolean;
var
  mSkip: TTextPosition;
begin
  for mSkip in Declared do
  begin
    if SamePosition(mSkip, APosition) then
    begin
      Exit(True);
    end;
  end;
  Result := InsideAny(APosition, Bodies);
end;

{ TSearchArea }

constructor TSearchArea.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
  FFiles := TList<TSearchFile>.Create;
  FForms := TList<string>.Create;
  FTexts := TDictionary<string, string>.Create;
  FRegistered := TDictionary<string, Boolean>.Create;
  FFormsState := 0;
end;

destructor TSearchArea.Destroy;
begin
  FTexts.Free;
  FRegistered.Free;
  FForms.Free;
  FFiles.Free;
  inherited;
end;

function TSearchArea.IsOwnFile(const AFile: string): Boolean;
begin
  Result := SameText(AFile, FContext.FileName);
end;

procedure TSearchArea.AddSource(ASeen: TDictionary<string, Integer>; const AProject: TRuleProject;
  const ASource: string);
var
  mEntry: TSearchFile;
  mPosition: Integer;
begin
  if ASeen.TryGetValue(UpperCase(ASource), mPosition) then
  begin
    // Gehört die Datei auch zu einem Projekt, das kein Test ist, zählt sie normal.
    if not AProject.IsTest then
    begin
      mEntry := FFiles[mPosition];
      mEntry.OnlyTests := False;
      mEntry.TestProject := '';
      FFiles[mPosition] := mEntry;
    end;
    Exit;
  end;
  mEntry := Default(TSearchFile);
  mEntry.FileName := ASource;
  mEntry.OnlyTests := AProject.IsTest;
  if AProject.IsTest then
  begin
    mEntry.TestProject := ChangeFileExt(ExtractFileName(AProject.FileName), '');
  end;
  ASeen.Add(UpperCase(ASource), FFiles.Count);
  FFiles.Add(mEntry);
end;

procedure TSearchArea.AddForms(const AProject: TRuleProject);
var
  mForm: string;
begin
  for mForm in AProject.Forms do
  begin
    if not FForms.Contains(mForm) then
    begin
      FForms.Add(mForm);
    end;
  end;
end;

procedure TSearchArea.Collect(const AProjects: TArray<TRuleProject>);
var
  mSeen: TDictionary<string, Integer>;
  mEntry: TSearchFile;
  mProject: TRuleProject;
  mSource: string;
begin
  mSeen := TDictionary<string, Integer>.Create;
  try
    // Die eigene Datei zuerst: Dort steht die häufigste Verwendung.
    mEntry := Default(TSearchFile);
    mEntry.FileName := FContext.FileName;
    FFiles.Add(mEntry);
    mSeen.Add(UpperCase(FContext.FileName), 0);
    for mProject in AProjects do
    begin
      for mSource in mProject.Sources do
      begin
        AddSource(mSeen, mProject, mSource);
      end;
      AddForms(mProject);
    end;
  finally
    mSeen.Free;
  end;
end;

function TSearchArea.TextOf(const AFile: string; out AText: string): Boolean;
begin
  if IsOwnFile(AFile) then
  begin
    AText := FContext.Text;
    Exit(True);
  end;
  if FTexts.TryGetValue(UpperCase(AFile), AText) then
  begin
    Exit(True);
  end;
  Result := FContext.ProjectFiles.ReadText(AFile, AText);
  if Result then
  begin
    FTexts.Add(UpperCase(AFile), AText);
  end;
end;

function TSearchArea.InForms(const AName: string): Boolean;
var
  mForm, mText: string;
  mModel: TFormModel;
begin
  for mForm in FForms do
  begin
    if not TextOf(mForm, mText) or not ContainsText(mText, AName) then
    begin
      Continue;
    end;
    mModel := TFormModel.Create(mText);
    try
      if mModel.Occurrences(AName) <> nil then
      begin
        Exit(True);
      end;
    finally
      mModel.Free;
    end;
  end;
  Result := False;
end;

function TSearchArea.FormUnreadable: Boolean;
var
  mForm, mText: string;
begin
  if FFormsState = 0 then
  begin
    FFormsState := 1;
    for mForm in FForms do
    begin
      if not TextOf(mForm, mText) then
      begin
        FFormsState := 2;
      end;
    end;
  end;
  Result := FFormsState = 2;
end;

function TSearchArea.MentionsRegisterCall(const AFile: string; out AUnknown: Boolean): Boolean;
var
  mCall: string;
begin
  Result := False;
  AUnknown := False;
  for mCall in RegisterCalls do
  begin
    case FContext.ProjectFiles.NameIn(AFile, mCall) of
      TRuleNameAnswer.Present:
        Result := True;
      TRuleNameAnswer.Unknown:
        AUnknown := True;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TSearchArea.FileRegisters(const AEntry: TSearchFile; const AShort: string): Boolean;
var
  mText: string;
  mUnknown: Boolean;
  mTree: TSyntaxTree;
begin
  if IsOwnFile(AEntry.FileName) then
  begin
    Exit(RegistersIn(FContext.Tree.Tokens, AShort));
  end;
  if not MentionsRegisterCall(AEntry.FileName, mUnknown) or mUnknown then
  begin
    Exit(mUnknown);
  end;
  if not TextOf(AEntry.FileName, mText) then
  begin
    Exit(True);
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := RegistersIn(mTree.Tokens, AShort);
  finally
    mTree.Free;
  end;
end;

function TSearchArea.IsRegistered(const AContainer: string): Boolean;
var
  mShort: string;
  mEntry: TSearchFile;
begin
  mShort := Copy(AContainer, LastDelimiter('.', AContainer) + 1, MaxInt);
  if FRegistered.TryGetValue(LowerCase(mShort), Result) then
  begin
    Exit;
  end;
  Result := False;
  for mEntry in FFiles do
  begin
    Result := FileRegisters(mEntry, mShort);
    if Result then
    begin
      Break;
    end;
  end;
  FRegistered.Add(LowerCase(mShort), Result);
end;

function TSearchArea.LiteralInFile(const AFile, AText, ALiteral: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  if IsOwnFile(AFile) then
  begin
    Exit(LiteralIn(FContext.Tree.Tokens, ALiteral));
  end;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := LiteralIn(mTree.Tokens, ALiteral);
  finally
    mTree.Free;
  end;
end;

function TSearchArea.InStrings(const AName: string): Boolean;
var
  mEntry: TSearchFile;
  mText, mLiteral: string;
begin
  mLiteral := '''' + AName + '''';
  for mEntry in FFiles do
  begin
    if TextOf(mEntry.FileName, mText) and ContainsText(mText, mLiteral) and
      LiteralInFile(mEntry.FileName, mText, mLiteral) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSearchArea.SearchedText(AWholeGroup: Boolean): string;
begin
  Result := cTexts[TPublicMembersText.Searched].Text + Counted(FFiles.Count, cTexts[TPublicMembersText.FileOne].Text,
    cTexts[TPublicMembersText.FileMany].Text);
  if FForms.Count > 0 then
  begin
    Result := Result + cTexts[TPublicMembersText.AndSep].Text + Counted(FForms.Count,
      cTexts[TPublicMembersText.FormOne].Text, cTexts[TPublicMembersText.FormMany].Text);
  end;
  if AWholeGroup then
  begin
    Result := Result + cTexts[TPublicMembersText.OfGroup].Text;
  end
  else
  begin
    Result := Result + cTexts[TPublicMembersText.OfProject].Text;
  end;
end;

{ TPublicMemberScan }

constructor TPublicMemberScan.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  const AOptions: TPublicMemberOptions);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FOptions := AOptions;
  FCache := TRuleDerived.Open(AContext);
  FLocal := TRuleDerived.UnitIndex(FCache, AContext);
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
  if FLineBreak = '' then
  begin
    FLineBreak := sLineBreak;
  end;
  FArea := TSearchArea.Create(AContext);
  // Optionen der Regel und deadCode.keep* aus den Einstellungen (#64) zusammen.
  FConsidered := TConsideredUsed.Create(AContext.Index, FLocal, TRuleDerived.CodeTokens(FCache, AContext),
    TRuleOptions.Strings(AContext.Options, 'keepAttributes', []) + AContext.KeepAttributes,
    TRuleOptions.Strings(AContext.Options, 'keepPatterns', []) + AContext.KeepPatterns);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  FResolver := TRuleDerived.Resolver(FCache, AContext);
end;

destructor TPublicMemberScan.Destroy;
begin
  FConsidered.Free;
  FArea.Free;
  inherited;
end;

function TPublicMemberScan.IsTarget(const AResolved: TResolvedSymbol; const ASymbol: TIndexSymbol;
  AAmbiguous: Boolean): Boolean;
begin
  Result := AResolved.Found and SameText(AResolved.Name, ASymbol.Name) and
    SameText(AResolved.Container, ASymbol.Container) and
    (SameText(AResolved.UnitName, FLocal.UnitName) or FArea.IsOwnFile(AResolved.FileName));
  // Bei eindeutig aufgelösten Überladungen zählt nur die passende.
  if Result and not AAmbiguous and (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) and
    ASymbol.HasDirective('overload') and (AResolved.ParamTypes <> nil) then
  begin
    Result := AnsiSameText(string.Join(',', AResolved.ParamTypes), string.Join(',', ASymbol.ParamTypes));
  end;
end;

function TPublicMemberScan.DeclaredAt(const AFile, AName: string): TArray<TTextPosition>;
var
  mIndexed: TUnitIndex;
  mSymbol: TIndexSymbol;
  mPosition: Integer;
begin
  Result := nil;
  if FArea.IsOwnFile(AFile) then
  begin
    for mPosition in FLocal.SymbolsNamed(AName) do
    begin
      Result := Result + [FLocal.Symbols[mPosition].SelectionRange.StartPos];
    end;
    Exit;
  end;
  if not FContext.Index.FindFile(AFile, mIndexed) then
  begin
    Exit;
  end;
  for mSymbol in mIndexed.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and (mSymbol.FileName = '') then
    begin
      Result := Result + [mSymbol.SelectionRange.StartPos];
    end;
  end;
end;

function TPublicMemberScan.OwnRanges(const ASymbol: TIndexSymbol): TArray<TTextRange>;
var
  mNode: TSyntaxNode;
  mWanted: string;
  mIsType: Boolean;
begin
  Result := nil;
  mWanted := QualifiedOf(ASymbol);
  mIsType := IsTypeSymbol(ASymbol);
  if mIsType then
  begin
    Result := [ASymbol.Range];
  end;
  for mNode in TRuleDerived.Routines(FCache, FContext) do
  begin
    if SameText(mNode.Name, mWanted) or (mIsType and StartsText(ASymbol.Name + '.', WithoutTypeParams(mNode.Name))) then
    begin
      Result := Result + [TTextRange.Create(mNode.StartPos, mNode.EndPos)];
    end;
  end;
end;

function TPublicMemberScan.ResolvesTo(ATree: TSyntaxTree; const AFile: string; const APosition: TTextPosition;
  const ASymbol: TIndexSymbol): Boolean;
var
  mResults: TArray<TResolvedSymbol>;
  mResolved: TResolvedSymbol;
begin
  if Assigned(FContext.Cancelled) and FContext.Cancelled() then
  begin
    raise ERuleCheckCancelled.Create(UnusedPublicMemberRuleId);
  end;
  mResults := FResolver.ResolveAll(ATree, AFile, APosition);
  if (mResults = nil) or not mResults[0].Found then
  begin
    Exit(True);
  end;
  for mResolved in mResults do
  begin
    if IsTarget(mResolved, ASymbol, Length(mResults) > 1) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPublicMemberScan.TokenUses(ATree: TSyntaxTree; const AFile: string; const ASymbol: TIndexSymbol;
  const AToken: TPascalToken; const AFilter: TOccurrenceFilter; const AShort: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  mName := CleanName(AToken.Text);
  // [Behalten] verwendet BehaltenAttribute; die Namensauflösung kennt die Kurzform nicht.
  if (AShort <> '') and SameText(mName, AShort) and not InsideAny(AToken.StartPos, AFilter.Bodies) then
  begin
    Exit(True);
  end;
  if SameText(mName, ASymbol.Name) and not AFilter.Excludes(AToken.StartPos) then
  begin
    Result := ResolvesTo(ATree, AFile, AToken.StartPos, ASymbol);
  end;
end;

function TPublicMemberScan.UsedInTree(ATree: TSyntaxTree; const AFile: string; const ASymbol: TIndexSymbol): Boolean;
var
  mFilter: TOccurrenceFilter;
  mShort: string;
  mIndex: Integer;
begin
  Result := False;
  mFilter.Declared := DeclaredAt(AFile, ASymbol.Name);
  mFilter.Bodies := nil;
  if FArea.IsOwnFile(AFile) then
  begin
    mFilter.Bodies := OwnRanges(ASymbol);
  end;
  mShort := AttributeShortName(ASymbol);
  FResolver.PinTree(ATree, AFile);
  try
    mIndex := 0;
    while not Result and (mIndex <= High(ATree.Tokens)) do
    begin
      Result := TokenUses(ATree, AFile, ASymbol, ATree.Tokens[mIndex], mFilter, mShort);
      Inc(mIndex);
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

function TPublicMemberScan.NameInFile(const AFile: string; const ASymbol: TIndexSymbol): TRuleNameAnswer;
begin
  Result := FContext.ProjectFiles.NameIn(AFile, ASymbol.Name);
  if (Result = TRuleNameAnswer.Absent) and (AttributeShortName(ASymbol) <> '') then
  begin
    Result := FContext.ProjectFiles.NameIn(AFile, AttributeShortName(ASymbol));
  end;
end;

function TPublicMemberScan.UsedIn(const AFile: string; const ASymbol: TIndexSymbol; out AUsed: Boolean): Boolean;
var
  mAnswer: TRuleNameAnswer;
  mText: string;
  mTree: TSyntaxTree;
begin
  AUsed := False;
  if FArea.IsOwnFile(AFile) then
  begin
    AUsed := UsedInTree(FContext.Tree, FContext.FileName, ASymbol);
    Exit(True);
  end;
  // Absent: sicher nicht verwendet; Unknown: nicht sicher.
  mAnswer := NameInFile(AFile, ASymbol);
  if mAnswer <> TRuleNameAnswer.Present then
  begin
    Exit(mAnswer = TRuleNameAnswer.Absent);
  end;
  Result := FArea.TextOf(AFile, mText);
  if not Result then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    AUsed := UsedInTree(mTree, AFile, ASymbol);
  finally
    mTree.Free;
  end;
end;

function TPublicMemberScan.FileUsage(const AEntry: TSearchFile; const ASymbol: TIndexSymbol): TUsage;
var
  mUsed: Boolean;
begin
  if not UsedIn(AEntry.FileName, ASymbol, mUsed) then
  begin
    Exit(TUsage.Used);
  end;
  if not mUsed then
  begin
    Exit(TUsage.Unused);
  end;
  if AEntry.OnlyTests and not FOptions.TestsCount then
  begin
    Exit(TUsage.OnlyTests);
  end;
  Result := TUsage.Used;
end;

function TPublicMemberScan.UsageOf(const ASymbol: TIndexSymbol; out ATestProject: string): TUsage;
var
  mEntry: TSearchFile;
  mUsage: TUsage;
begin
  ATestProject := '';
  Result := TUsage.Unused;
  for mEntry in FArea.Files do
  begin
    mUsage := FileUsage(mEntry, ASymbol);
    if mUsage = TUsage.Used then
    begin
      Exit(TUsage.Used);
    end;
    if (mUsage = TUsage.OnlyTests) and (ATestProject = '') then
    begin
      ATestProject := mEntry.TestProject;
    end;
    if mUsage = TUsage.OnlyTests then
    begin
      Result := TUsage.OnlyTests;
    end;
  end;
  if FArea.InForms(ASymbol.Name) or (FOptions.StringsCount and FArea.InStrings(ASymbol.Name)) then
  begin
    Result := TUsage.Used;
  end;
end;

function TPublicMemberScan.IgnoreFix(const ASymbol: TIndexSymbol): TRuleFix;
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
  Result := TRuleFix.Create(cTexts[TPublicMembersText.MarkPublic].Text,
    [TTextEdit.Create(TTextRange.Create(mLine, 0, mLine, 0), mIndent + '// lsp-ignore: ' +
    UnusedPublicMemberRuleId + FLineBreak)]);
  Result.Alternative := True;
end;

function TPublicMemberScan.IsExempt(const ASymbol: TIndexSymbol): Boolean;
begin
  if FConsidered.Reason(ASymbol) <> TConsideredUsedReason.None then
  begin
    Exit(True);
  end;
  if (ASymbol.Visibility = TIndexVisibility.Published) and (ASymbol.Container <> '') and
    (((ASymbol.Kind = TIndexSymbolKind.Method) and FArea.FormUnreadable) or FArea.IsRegistered(ASymbol.Container)) then
  begin
    Exit(True);
  end;
  // Registrierte Klassen erreichen Streaming und Objektinspektor über RTTI (#64).
  Result := IsTypeSymbol(ASymbol) and FArea.IsRegistered(ASymbol.Name);
end;

procedure TPublicMemberScan.CheckSymbol(const ASymbol: TIndexSymbol);
var
  mTestProject: string;
begin
  if IsExempt(ASymbol) then
  begin
    Exit;
  end;
  case UsageOf(ASymbol, mTestProject) of
    TUsage.Unused:
      FReport.AddWithDetails(ASymbol.SelectionRange, cTexts[TPublicMembersText.NeverUsed].Fmt(
        [KindText(ASymbol), QualifiedOf(ASymbol)]), FArea.SearchedText(FOptions.WholeGroup), TRuleConfidence.Medium,
        [IgnoreFix(ASymbol)]);
    TUsage.OnlyTests:
      FReport.AddWithDetails(ASymbol.SelectionRange, cTexts[TPublicMembersText.OnlyUsedIn].Fmt(
        [KindText(ASymbol), QualifiedOf(ASymbol), mTestProject]), FArea.SearchedText(FOptions.WholeGroup),
        TRuleConfidence.Medium, [IgnoreFix(ASymbol)]);
  else
    // Verwendet: nichts zu melden.
  end;
end;

procedure TPublicMemberScan.Run(const AProjects: TArray<TRuleProject>);
var
  mSymbol: TIndexSymbol;
  mSeen: TDictionary<string, Boolean>;
begin
  FArea.Collect(AProjects);
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in FLocal.Symbols do
    begin
      if FirstDeclaration(mSymbol, mSeen) and FOptions.Wanted(mSymbol) then
      begin
        CheckSymbol(mSymbol);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

{ TUnusedPublicMemberRule }

function TUnusedPublicMemberRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnusedPublicMemberRuleId, TRuleSeverity.Hint,
    cTexts[TPublicMembersText.Title].Text);
end;

/// <summary>Hat der Lauf Baum, Projektdateien, Index und Dateinamen, und bindet die Unit nichts ein?</summary>
function CanCheck(const AContext: TRuleContext): Boolean;
begin
  Result := (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) and (AContext.ProjectFiles <> nil) and
    (AContext.Index <> nil) and (AContext.FileName <> '');
  Result := Result and not HasIncludes(AContext.Tree.Tokens);
end;

procedure TUnusedPublicMemberRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TPublicMemberOptions;
  mProjects: TArray<TRuleProject>;
  mReason: string;
  mScan: TPublicMemberScan;
begin
  if not CanCheck(AContext) then
  begin
    Exit;
  end;
  mOptions := TPublicMemberOptions.Read(AContext.Options);
  mProjects := AContext.ProjectFiles.ProjectsOf(AContext.FileName, mOptions.WholeGroup);
  if (mProjects = nil) or not mOptions.KindsAllowed(mProjects, AContext.FileName) or
    not AContext.ProjectFiles.Complete(mReason) then
  begin
    Exit;
  end;
  mScan := TPublicMemberScan.Create(AContext, AReport, mOptions);
  try
    mScan.Run(mProjects);
  finally
    mScan.Free;
  end;
end;

procedure RegisterPublicMemberRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnusedPublicMemberRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.PublicMembers', cTexts);

end.
