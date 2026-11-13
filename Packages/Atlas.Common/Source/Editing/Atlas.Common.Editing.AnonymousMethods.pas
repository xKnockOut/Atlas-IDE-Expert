unit Atlas.Common.Editing.AnonymousMethods;

// Anonyme Methode und Methode ineinander umwandeln (#680):
//   In Methode umwandeln (auf dem Kopf einer anonymen Methode in einer
//     Methode): Der Rumpf wird private Methode der Klasse, die Deklaration
//     steht im private-Abschnitt (legt ihn an, wenn er fehlt), der Rumpf
//     hinter der äußeren Methode. In einer freien Routine wird er eine Routine
//     der Unit vor ihr („In Routine umwandeln“); eine lokale Routine ginge
//     nicht, weil Delphi lokale Routinen nicht als Wert annimmt (E2094).
//     Der Name kommt aus dem Zusammenhang (OnClick := … → HandleClick,
//     TComparer<T>.Construct(function(const A, B: T) … A.Name …) →
//     CompareByName, ForEach → ProcessItem, TParallel.For → ProcessIndex) und
//     ist im Client änderbar.
//     Ohne erfasste Variablen steht an der Stelle der Methodenname; das passt
//     auf Methodenzeiger (of object) wie auf reference to.
//     Erfasste Variablen (Parameter, Variablen und Inline-Variablen der
//     äußeren Routine) werden Parameter der Methode: var, wenn die anonyme
//     Methode sie schreibt (auch als var-Argument), const bei Strings,
//     Records und Interfaces. An der Stelle bleibt eine kurze anonyme
//     Methode, die die Methode mit ihren Parametern und den Variablen aufruft.
//     Bei synchronen Aufrufen (Sort, ForEach, TParallel.For, Synchronize …)
//     ist das die übliche Form. Läuft die anonyme Methode später (Queue,
//     TTask.Run, Zuweisung an Ereignis oder Variable), kann eine benannte
//     Methode die Variablen nicht erfassen: Die Weiterleitung hält sie weiter
//     fest, das Verhalten bleibt gleich. Mit refactoring.anonymousMethod-
//     DeferredCapture = fields kopiert Atlas die Werte stattdessen vor der
//     Anweisung in Felder und setzt den Methodennamen ein; das ändert die
//     Bedeutung (spätere Änderungen sieht die Methode nicht, gleichzeitig
//     wartende Aufrufe teilen die Felder) und geht nur in Methoden ohne
//     geschriebene Variablen, sonst bleibt es bei der Weiterleitung.
//     Konstanten der äußeren Routine wandern als Konstanten mit. Die
//     Vorschau nennt die Form und warum.
//   Als anonyme Methode einbetten (auf einer privaten Methode, die genau
//     einmal als Wert an ein reference to übergeben oder zugewiesen und nie
//     aufgerufen wird, im Rumpf einer Methode derselben Klasse; nicht für
//     Methoden, die in der Formulardatei stehen): Der Rumpf steht an der
//     Stelle als anonyme Methode, die Methode entfällt.
// Nicht angeboten wird, wenn sich die Bedeutung eines Namens ändern könnte:
// Result der äußeren Routine, lokale Routinen oder Typen der äußeren, with,
// inherited, eine verschachtelte anonyme Methode, die eine künftige
// var-Variable erfasst; beim Einbetten ein Name des Aufrufers, der einen
// Namen des Rumpfs verdeckt. Jede Umwandlung ist ein Rückgängig-Schritt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.AnonymousMethods.Shared;

type
  TDeferredCapture = Atlas.Common.Editing.AnonymousMethods.Shared.TDeferredCapture;
  TProcTypeKind = Atlas.Common.Editing.AnonymousMethods.Shared.TProcTypeKind;
  TAnonymousForm = Atlas.Common.Editing.AnonymousMethods.Shared.TAnonymousForm;
  TAnonymousLookup = Atlas.Common.Editing.AnonymousMethods.Shared.TAnonymousLookup;
  TAnonymousInput = Atlas.Common.Editing.AnonymousMethods.Shared.TAnonymousInput;

  TAnonymousTarget = record
    /// <summary>Methode der Klasse; sonst Routine der Unit.</summary>
    IsMethod: Boolean;
    Suggested: string;
    Form: TAnonymousForm;
    /// <summary>Titel der Code-Aktion, z. B. „In Methode umwandeln (HandleClick)“.</summary>
    function Title: string;
  end;

  TAnonymousResult = record
    Edits: TArray<TTextEdit>;
    Warnings: TArray<string>;
    /// <summary>Neuer Kopf und Erklärung der Form.</summary>
    Preview: string;
    Form: TAnonymousForm;
  end;

  TAnonymousMethods = class
  public
    /// <summary>Titel „In Methode umwandeln“ in der Sprache der Servertexte.</summary>
    class function ToMethodTitle: string; static;
    /// <summary>Titel „In Routine umwandeln“ in der Sprache der Servertexte.</summary>
    class function ToRoutineTitle: string; static;
    /// <summary>Titel „Als anonyme Methode einbetten“ (wie EmbedTitle der Unit Shared).</summary>
    class function EmbedTitle: string; static;
    /// <summary>Geht „In Methode umwandeln“ an AInput.Position (Kopf einer anonymen Methode), ohne Prüfung des
    /// Namens? ATarget nennt Ziel, Vorschlag und Form, sonst AReason den Grund.</summary>
    class function Target(const AInput: TAnonymousInput; out ATarget: TAnonymousTarget;
      out AReason: string): Boolean; static;
    /// <summary>„In Methode umwandeln“ an AInput.Position mit dem Namen AName.</summary>
    class function Execute(const AInput: TAnonymousInput; const AName: string; out AResult: TAnonymousResult;
      out AReason: string): Boolean; static;
    /// <summary>„Als anonyme Methode einbetten“ für die Methode, deren Kopf (Implementierung oder Klasse)
    /// AInput.Position enthält; AReason nennt, warum es nicht geht.</summary>
    class function Embed(const AInput: TAnonymousInput; out AAction: TCodeAction;
      out AReason: string): Boolean; static;
    /// <summary>Art des Typtexts ohne Namensauflösung: reference to, of object, procedure, bekannte Typen der RTL
    /// (TProc, TFunc&lt;T&gt;, TComparison&lt;T&gt;, TNotifyEvent …); sonst Unknown.</summary>
    class function KindOfTypeText(const ATypeText: string): TProcTypeKind; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Editing.AnonymousMethods.Embed,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Pascal.TokenCursor;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingAnonymousMethodsText = (NoTree, NoAnonymousMethod, NotInARoutine, LiesInALocalRoutine,
    LiesInAnotherAnonymousMethod, UnsupportedClass, ClassNotInTheFile, UnsupportedParameters, UsesResultOfTheOuter,
    UsesTheLocalRoutine, UsesTheLocalType, WritesTheConstant, TypeOfUnknown, TheAnonymousMethodWritesCaptured,
    NothingCanBeInsertedBefore, ANestedAnonymousMethodCaptures, IsNotAValidName, IsAlreadyTaken, BodyNotReadable,
    ClassDeclarationCannotBeExtended, RunsDuringTheCapturedVariables, MayRunLaterANamed, NotPossibleAsFieldsHere,
    CapturesNoVariablesTheSite, RunsLaterTheValuesOf, ReadsTheValuesFromFields, RoutineWithoutHeader,
    OnlyInMethodsOfAn, NewMethod, NewRoutine, ToMethodTitle, ToRoutineTitle);

const
  cTexts: array[TEditingAnonymousMethodsText] of TAtlasText = (
    (De: 'kein Baum'; En: 'no tree'),
    (De: 'keine anonyme Methode'; En: 'no anonymous method'),
    (De: 'nicht in einer Routine'; En: 'not in a routine'),
    (De: 'liegt in einer lokalen Routine'; En: 'lies in a local routine'),
    (De: 'liegt in einer anderen anonymen Methode'; En: 'lies in another anonymous method'),
    (De: 'nicht unterstützte Klasse'; En: 'unsupported class'),
    (De: 'Klasse %s nicht in der Datei'; En: 'Class %s not in the file'),
    (De: 'nicht unterstützte Parameter'; En: 'unsupported parameters'),
    (De: 'nutzt Result der äußeren Routine'; En: 'uses Result of the outer routine'),
    (De: 'nutzt die lokale Routine '; En: 'uses the local routine '),
    (De: 'nutzt den lokalen Typ '; En: 'uses the local type '),
    (De: 'schreibt die Konstante '; En: 'writes the constant '),
    (De: 'Typ von %s unbekannt'; En: 'Type of %s unknown'),
    (De: 'die anonyme Methode schreibt erfasste Variablen'; En: 'the anonymous method writes captured variables'),
    (De: 'vor der Anweisung lässt sich nichts einfügen'; En: 'nothing can be inserted before the statement'),
    (De: 'eine verschachtelte anonyme Methode fängt %s ein'; En: 'a nested anonymous method captures %s'),
    (De: '"%s" ist kein gültiger Name'; En: '"%s" is not a valid name'),
    (De: '"%s" ist schon vergeben'; En: '"%s" is already taken'),
    (De: 'Rumpf nicht lesbar'; En: 'body not readable'),
    (De: 'Klassendeklaration nicht erweiterbar'; En: 'class declaration cannot be extended'),
    (De: 'Läuft während %s: Die erfassten Variablen (%s) werden Parameter, geschriebene als var; an der Stelle ruft ' +
      'eine kurze anonyme Methode %s mit ihnen auf.';
     En: 'Runs during %s: the captured variables (%s) become parameters, written ones as var; at the site a short ' +
      'anonymous method calls %s with them.'),
    (De: 'Läuft womöglich später: Eine benannte Methode kann %s nicht erfassen. An der Stelle bleibt eine kurze ' +
      'anonyme Weiterleitung, die die Variablen weiter festhält und %s mit ihnen aufruft; das Verhalten bleibt ' +
      'gleich.';
     En: 'May run later: a named method cannot capture %s. At the site a short anonymous forwarder remains, which ' +
      'keeps holding the variables and calls %s with them; the behavior stays the same.'),
    (De: 'Als Felder geht hier nicht: %s.'; En: 'Not possible as fields here: %s.'),
    (De: 'Erfasst keine Variablen: An der Stelle steht jetzt %s.';
     En: 'Captures no variables: the site now reads %s.'),
    (De: 'Läuft später: Die Werte von %s kommen vor der Anweisung in Felder, an der Stelle steht %s.';
     En: 'Runs later: the values of %s go into fields before the statement, the site reads %s.'),
    (De: '%s liest die Werte aus Feldern: Spätere Änderungen von %s sieht es nicht, und gleichzeitig wartende ' +
      'Aufrufe teilen sich die Felder.';
     En: '%s reads the values from fields: it does not see later changes of %s, and calls waiting at the same time ' +
      'share the fields.'),
    (De: 'Routine ohne Kopf'; En: 'routine without header'),
    (De: 'nur in Methoden eines Objekts'; En: 'only in methods of an object'),
    (De: 'Neue Methode: '; En: 'New method: '),
    (De: 'Neue Routine: '; En: 'New routine: '),
    (De: 'In Methode umwandeln'; En: 'Convert to method'),
    (De: 'In Routine umwandeln'; En: 'Convert to routine'));

{$SCOPEDENUMS OFF}

const
  // Rufen die anonyme Methode, solange der Aufruf läuft.
  cSyncCalls: array[0..5] of string = ('Sort', 'ForEach', 'For', 'Synchronize', 'BinarySearch', 'TryFind');
  cMainThreadCalls: array[0..2] of string = ('Synchronize', 'Queue', 'ForceQueue');
  cBackgroundCalls: array[0..4] of string = ('Run', 'Future', 'CreateAnonymousThread', 'Start', 'StartFuture');
  cReferenceTypes: array[0..7] of string = ('TProc', 'TFunc', 'TPredicate', 'TComparison', 'TThreadProcedure',
    'TEqualityComparison', 'THasher', 'TListSortCompareFunc');
  cMethodPointerTypes: array[0..9] of string = ('TNotifyEvent', 'TThreadMethod', 'TKeyEvent', 'TKeyPressEvent',
    'TMouseEvent', 'TMouseMoveEvent', 'TCloseEvent', 'TCloseQueryEvent', 'TGetStrProc', 'THelpEvent');


type
  /// <summary>Name der äußeren Routine, den die anonyme Methode nutzt.</summary>
  TAnonymousCaptured = record
    Local: TRoutineLocal;
    TypeText: string;
    Written: Boolean;
    /// <summary>In einer verschachtelten anonymen Methode benutzt (darf kein var-Parameter werden).</summary>
    InNested: Boolean;
    /// <summary>Feldname bei der Form Fields.</summary>
    Field: string;
  end;

  /// <summary>Was an der Stelle umgewandelt wird: Ergebnis der Prüfung.</summary>
  TAnonymousSite = record
    Input: TAnonymousInput;
    Tokens: TArray<TPascalToken>;
    /// <summary>Gehört der Prüfung (TSiteAnalysis).</summary>
    Cache: TLocalsCache;
    Anonymous: TSyntaxNode;
    Outer: TSyntaxNode;
    ClassName: string;
    TypeBody: TSyntaxNode;
    IsMethod: Boolean;
    IsClass: Boolean;
    IsStatic: Boolean;
    Parameters: TArray<TParameterText>;
    Captured: TArray<TAnonymousCaptured>;
    ConstLines: TArray<string>;
    /// <summary>Wird die anonyme Methode synchron aufgerufen? CallName: Name des Aufrufs ('' ohne).</summary>
    Synchronous: Boolean;
    CallName: string;
    Form: TAnonymousForm;
    /// <summary>Warum Fields nicht ging, obwohl eingestellt; '' sonst.</summary>
    FieldsReason: string;
    Suggested: string;
  end;

  /// <summary>Prüft, ob und wie die anonyme Methode an der Stelle umgewandelt werden kann.</summary>
  TSiteAnalysis = class
  private
    FSite: TAnonymousSite;
    /// <summary>Belegte Einträge in FSite.Captured während des Sammelns.</summary>
    FCount: Integer;
    function LocateReason: string;
    function ContentReason: string;
    function ClassReason: string;
    function ReadClass(AHeader: TSyntaxNode): string;
    function ParameterReason: string;
    function CollectCaptured: string;
    function IdentifiersReason(AIdentifiers: TList<TSyntaxNode>; const AOuterLocals: TArray<TRoutineLocal>): string;
    function IdentifierReason(ANode: TSyntaxNode; const AOuterLocals: TArray<TRoutineLocal>): string;
    function OuterIndex(ANode: TSyntaxNode; const AOuterLocals: TArray<TRoutineLocal>): Integer;
    function OuterNameReason(const AName: string; ARoutines: Boolean): string;
    function TypeReferencesReason(AIdentifiers: TList<TSyntaxNode>): string;
    function AddConstant(ANode: TSyntaxNode; const ALocal: TRoutineLocal; AWritten: Boolean): string;
    function CapturedIndex(const ALocal: TRoutineLocal): Integer;
    procedure AddCaptured(ANode: TSyntaxNode; const ALocal: TRoutineLocal; AWritten: Boolean);
    procedure ClassifyUse;
    function ChooseForm: string;
    function UnknownTypeReason: string;
    function FieldsProblem: string;
    function NestedReason: string;
    function SuggestName: string;
    function ArgumentName: string;
    function CompareName: string;
  public
    constructor Create(const AInput: TAnonymousInput);
    destructor Destroy; override;
    function Analyze(out AReason: string): Boolean;
    property Site: TAnonymousSite read FSite;
  end;

  /// <summary>Baut die Änderungen für „In Methode umwandeln“ aus einer geprüften Stelle.</summary>
  TSiteBuilder = class
  private
    FSite: TAnonymousSite;
    FName: string;
    FLineBreak: string;
    /// <summary>Parameter der neuen Methode: die eigenen, bei der Weiterleitung dazu die erfassten.</summary>
    FParameters: TArray<TParameterText>;
    FEdits: TArray<TTextEdit>;
    function NameReason: string;
    procedure AddForwardParameters;
    function ReadsAsConst(const ACaptured: TAnonymousCaptured): Boolean;
    function ModifierOf(const ACaptured: TAnonymousCaptured): string;
    procedure NameFields;
    function FieldTaken(const AField: string): Boolean;
    function FieldName(const ALocalName: string; const ATaken: TArray<string>): string;
    function CapturedField(ANode: TSyntaxNode): string;
    function FieldEdits: TArray<TOffsetEdit>;
    function OneLineBody(const AEdits: TArray<TOffsetEdit>; const AIndent: string; out ABody: string): Boolean;
    function MultiLineBody(const AEdits: TArray<TOffsetEdit>; const AIndent: string): string;
    function ConstBlock(const AIndent: string): string;
    function MethodText(out AText: string; out AReason: string): Boolean;
    function ArgumentList: string;
    function CallSite: string;
    procedure AddFieldAssignments;
    function AddFieldsDeclaration(var ADeclaration: string): string;
    function AddMethodEdits(const AMoved: string): string;
    procedure AddRoutineEdit(const AMoved: string);
    function ForwardingExplanation(const ANames: string): string;
    function FormExplanation: string;
    function Preview: string;
    function Warnings: TArray<string>;
  public
    constructor Create(const ASite: TAnonymousSite; const AName: string);
    function Build(ACheckName: Boolean; out AResult: TAnonymousResult; out AReason: string): Boolean;
  end;

{ Hilfen }

/// <summary>Gültiger Bezeichner, kein reserviertes Wort?</summary>
function IsValidName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TPascalLexer.IsReservedWord(AName);
end;

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>AItems mit ASeparator verbunden.</summary>
function Joined(const AItems: TArray<string>; const ASeparator: string): string;
var
  mItem: string;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ASeparator;
    end;
    Result := Result + mItem;
  end;
end;

/// <summary>Handler-Name zu einem Ziel: OnClick → HandleClick, FCallback → HandleCallback.</summary>
function HandlerName(const ATarget: string): string;
begin
  Result := ATarget;
  if (Length(Result) > 2) and StartsText('On', Result) and CharInSet(Result[3], ['A'..'Z']) then
  begin
    Result := Copy(Result, 3, MaxInt);
  end
  else if (Length(Result) > 1) and CharInSet(Result[1], ['F', 'L']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  Result := 'Handle' + Capitalized(Result);
end;

/// <summary>Ende des Kopfs einer anonymen Methode: Beginn von var, const bzw. begin; sonst ihr Ende.</summary>
function HeadEnd(AAnonymous: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := AAnonymous.EndOffset;
  // Rückwärts: Die letzte Zuweisung ist der erste passende Abschnitt.
  for mIndex := AAnonymous.ChildCount - 1 downto 0 do
  begin
    if AAnonymous[mIndex].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.Block] then
    begin
      Result := AAnonymous[mIndex].StartOffset;
    end;
  end;
end;

/// <summary>Innerste anonyme Methode, deren Kopf (bis vor var, const oder begin) AOffset enthält; nil ohne.</summary>
function AnonymousAt(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mFound: TSyntaxNode;
  mOffset: Integer;
begin
  mFound := nil;
  mOffset := AOffset;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := TRoutineParts.Encloses(ANode, mOffset);
      if Result and (ANode.Kind = TSyntaxKind.AnonymousMethod) and (mOffset < HeadEnd(ANode)) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

/// <summary>Innerste Routine um ANode; nil ohne.</summary>
function RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Kurzer Name des Aufgerufenen: Sort aus FList.Sort, For aus TParallel.For.</summary>
function CalleeName(ACall: TSyntaxNode): string;
begin
  Result := '';
  if (ACall <> nil) and (ACall.Kind = TSyntaxKind.Call) and (ACall.ChildCount > 0) then
  begin
    Result := ACall[0].Name;
  end;
end;

/// <summary>Ist AName ein Parametername?</summary>
function IsParameterName(const AParameters: TArray<TParameterText>; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(AParameters) do
  begin
    if SameText(AParameters[mIndex].Name, AName) then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Deklariert ATypeBody die Methode AName als static?</summary>
function DeclaredStatic(const ATokens: TArray<TPascalToken>; ATypeBody: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
begin
  Result := False;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    mNode := ATypeBody[mIndex];
    if (mNode.Kind = TSyntaxKind.RoutineHeader) and SameText(mNode.Name, AName) and
      TRoutineParts.HasWord(ATokens, mNode, ['static']) then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Hat ATypeBody einen private-Abschnitt?</summary>
function HasPrivateSection(ATypeBody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if (ATypeBody[mIndex].Kind = TSyntaxKind.Visibility) and MatchText(ATypeBody[mIndex].Name, ['private',
      'strict private']) then
    begin
      Result := True;
    end;
  end;
end;

function AnyWritten(const ACaptured: TArray<TAnonymousCaptured>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(ACaptured) do
  begin
    if ACaptured[mIndex].Written then
    begin
      Result := True;
    end;
  end;
end;

function CapturedNames(const ACaptured: TArray<TAnonymousCaptured>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ACaptured));
  for mIndex := 0 to High(ACaptured) do
  begin
    Result[mIndex] := ACaptured[mIndex].Local.Name;
  end;
end;

/// <summary>Art eines Typnamens ohne reference to, of object oder procedure: bekannte Typen der RTL.</summary>
function KindOfTypeName(const AName: string): TProcTypeKind;
var
  mName: string;
begin
  mName := AName;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  mName := Trim(Copy(mName, LastDelimiter('.', mName) + 1, MaxInt));
  if MatchText(mName, cReferenceTypes) then
  begin
    Result := TProcTypeKind.Reference;
  end
  else if MatchText(mName, cMethodPointerTypes) then
  begin
    Result := TProcTypeKind.MethodPointer;
  end
  else
  begin
    Result := TProcTypeKind.Unknown;
  end;
end;

{ Namen an der Stelle }

/// <summary>Vergebene Namen: Mitglieder der Klasse bzw. Namen der Unit.</summary>
function SiteTaken(const ASite: TAnonymousSite): TArray<string>;
begin
  if ASite.IsMethod then
  begin
    Result := TRoutineBody.MemberNames(ASite.TypeBody);
  end
  else
  begin
    Result := TRoutineParts.UnitNames(ASite.Input.Tree.Root);
  end;
end;

/// <summary>Mitglied der Klasse samt Vorfahren mit dem Namen AName?</summary>
function MemberTaken(const ASite: TAnonymousSite; const AName: string): Boolean;
begin
  Result := ASite.IsMethod and Assigned(ASite.Input.Lookup.MemberExists) and
    ASite.Input.Lookup.MemberExists(ASite.ClassName, AName, ASite.Anonymous.StartOffset);
end;

/// <summary>Verdeckte ein Name der äußeren Routine an der Stelle die neue Methode AName?</summary>
function OuterTaken(const ASite: TAnonymousSite; const AName: string): Boolean;
begin
  Result := ASite.Cache.Declares(ASite.Outer, AName, ASite.Anonymous.StartOffset) or
    SameText(AName, ASite.Outer.Name) or SameText(AName, TRoutineBody.ShortNameOf(ASite.Outer.Name));
end;

function SiteNameTaken(const ASite: TAnonymousSite; const AName: string): Boolean;
begin
  Result := (IndexText(AName, SiteTaken(ASite)) >= 0) or MemberTaken(ASite, AName) or OuterTaken(ASite, AName) or
    IsParameterName(ASite.Parameters, AName);
end;

/// <summary>AName mit der Klasse davor, wenn die neue Routine eine Methode ist.</summary>
function Qualified(const ASite: TAnonymousSite; const AName: string): string;
begin
  Result := AName;
  if ASite.IsMethod then
  begin
    Result := ASite.ClassName + '.' + AName;
  end;
end;

{ TAnonymousTarget }

function TAnonymousTarget.Title: string;
begin
  if IsMethod then
  begin
    Result := TAnonymousMethods.ToMethodTitle;
  end
  else
  begin
    Result := TAnonymousMethods.ToRoutineTitle;
  end;
  Result := Format('%s (%s)', [Result, Suggested]);
end;

{ TSiteAnalysis }

constructor TSiteAnalysis.Create(const AInput: TAnonymousInput);
begin
  inherited Create;
  FSite := Default(TAnonymousSite);
  FSite.Input := AInput;
end;

destructor TSiteAnalysis.Destroy;
begin
  FSite.Cache.Free;
  inherited;
end;

function TSiteAnalysis.Analyze(out AReason: string): Boolean;
begin
  AReason := LocateReason;
  if AReason = '' then
  begin
    AReason := ContentReason;
  end;
  if AReason = '' then
  begin
    AReason := ClassReason;
  end;
  if AReason = '' then
  begin
    AReason := ParameterReason;
  end;
  if AReason = '' then
  begin
    FSite.Cache := TLocalsCache.Create(FSite.Input.Text, FSite.Input.Tree);
    AReason := CollectCaptured;
  end;
  if AReason = '' then
  begin
    ClassifyUse;
    AReason := ChooseForm;
  end;
  Result := AReason = '';
  if Result then
  begin
    FSite.Suggested := SuggestName;
  end;
end;

/// <summary>Anonyme Methode an der Stelle und äußere Routine.</summary>
function TSiteAnalysis.LocateReason: string;
var
  mTree: TSyntaxTree;
begin
  mTree := FSite.Input.Tree;
  if (mTree = nil) or (mTree.Root = nil) then
  begin
    Exit(cTexts[TEditingAnonymousMethodsText.NoTree].Text);
  end;
  FSite.Tokens := mTree.Tokens;
  FSite.Anonymous := AnonymousAt(mTree, TLineTable.Build(FSite.Input.Text).OffsetAt(FSite.Input.Position));
  if (FSite.Anonymous = nil) or (TRoutineBody.BodyOf(FSite.Anonymous) = nil) then
  begin
    Exit(cTexts[TEditingAnonymousMethodsText.NoAnonymousMethod].Text);
  end;
  FSite.Outer := RoutineOf(FSite.Anonymous);
  if (FSite.Outer = nil) or (TRoutineBody.BodyOf(FSite.Outer) = nil) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.NotInARoutine].Text;
  end
  else if FSite.Outer <> TAnonymousSyntax.TopRoutineOf(FSite.Anonymous) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.LiesInALocalRoutine].Text;
  end
  else if TRoutineParts.InAnonymous(FSite.Anonymous, FSite.Outer) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.LiesInAnotherAnonymousMethod].Text;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>with und inherited änderten die Bedeutung von Namen.</summary>
function TSiteAnalysis.ContentReason: string;
begin
  if TAnonymousSyntax.Inside(FSite.Anonymous, FSite.Outer, TSyntaxKind.WithStatement) or
    TRoutineLocals.HasKind(FSite.Anonymous, TSyntaxKind.WithStatement) then
  begin
    Result := 'with';
  end
  else if TAnonymousSyntax.HasInherited(FSite.Tokens, FSite.Anonymous) then
  begin
    Result := 'inherited';
  end
  else
  begin
    Result := '';
  end;
end;

function TSiteAnalysis.ClassReason: string;
var
  mHeader: TSyntaxNode;
begin
  FSite.ClassName := TRoutineBody.QualifierOf(FSite.Outer.Name);
  FSite.IsMethod := FSite.ClassName <> '';
  mHeader := TRoutineParts.HeaderOf(FSite.Outer);
  if (Pos('<', FSite.ClassName) > 0) or (Pos('.', FSite.ClassName) > 0) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.UnsupportedClass].Text;
  end
  else if mHeader = nil then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.RoutineWithoutHeader].Text;
  end
  else if FSite.IsMethod then
  begin
    Result := ReadClass(mHeader);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Klasse der äußeren Methode: Typrumpf, Klassenmethode, static.</summary>
function TSiteAnalysis.ReadClass(AHeader: TSyntaxNode): string;
begin
  Result := '';
  FSite.TypeBody := TRoutineBody.TypeBody(FSite.Input.Tree.Root, FSite.ClassName);
  if FSite.TypeBody = nil then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.ClassNotInTheFile].Fmt([FSite.ClassName]);
  end
  else
  begin
    FSite.IsClass := TRoutineParts.IsClassHeader(FSite.Tokens, AHeader);
    FSite.IsStatic := FSite.IsClass and DeclaredStatic(FSite.Tokens, FSite.TypeBody,
      TRoutineBody.ShortNameOf(FSite.Outer.Name));
  end;
end;

function TSiteAnalysis.ParameterReason: string;
begin
  Result := '';
  FSite.Parameters := TRoutineParts.ParameterTexts(FSite.Input.Text, FSite.Anonymous);
  if TAnonymousSyntax.UnreadParameters(FSite.Parameters, FSite.Anonymous) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.UnsupportedParameters].Text;
  end;
end;

/// <summary>Erfasste Variablen und Konstanten der äußeren Routine; Grund, wenn ein Name nicht mitwandern kann.
/// </summary>
function TSiteAnalysis.CollectCaptured: string;
var
  mIdentifiers: TList<TSyntaxNode>;
  mOuterLocals: TArray<TRoutineLocal>;
begin
  FSite.ConstLines := nil;
  mOuterLocals := FSite.Cache.Locals(FSite.Outer);
  // Jede äußere Lokale höchstens einmal: Länge vorab, am Ende auf FCount kürzen.
  FSite.Captured := nil;
  SetLength(FSite.Captured, Length(mOuterLocals));
  FCount := 0;
  mIdentifiers := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FSite.Anonymous, TSyntaxKind.Identifier, mIdentifiers);
    Result := IdentifiersReason(mIdentifiers, mOuterLocals);
    if Result = '' then
    begin
      // Lokale Typen der äußeren Routine auch in Typangaben.
      mIdentifiers.Clear;
      TRoutineLocals.CollectKind(FSite.Anonymous, TSyntaxKind.TypeReference, mIdentifiers);
      Result := TypeReferencesReason(mIdentifiers);
    end;
  finally
    SetLength(FSite.Captured, FCount);
    mIdentifiers.Free;
  end;
end;

function TSiteAnalysis.IdentifiersReason(AIdentifiers: TList<TSyntaxNode>;
  const AOuterLocals: TArray<TRoutineLocal>): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex < AIdentifiers.Count) do
  begin
    Result := IdentifierReason(AIdentifiers[mIndex], AOuterLocals);
    Inc(mIndex);
  end;
end;

function TSiteAnalysis.IdentifierReason(ANode: TSyntaxNode; const AOuterLocals: TArray<TRoutineLocal>): string;
var
  mFound: Integer;
  mWritten: Boolean;
begin
  Result := '';
  if TRoutineParts.Shadowed(FSite.Cache, ANode, FSite.Anonymous, ANode.Name, True) then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'Result') and TRoutineParts.IsFunction(FSite.Outer) then
  begin
    Exit(cTexts[TEditingAnonymousMethodsText.UsesResultOfTheOuter].Text);
  end;
  mFound := OuterIndex(ANode, AOuterLocals);
  if mFound < 0 then
  begin
    Exit(OuterNameReason(ANode.Name, True));
  end;
  mWritten := TRoutineLocals.AccessOf(ANode, FSite.Input.Lookup.Flow) <> TLocalAccess.Read;
  if AOuterLocals[mFound].Kind = TRoutineLocalKind.Constant then
  begin
    Result := AddConstant(ANode, AOuterLocals[mFound], mWritten);
  end
  else
  begin
    AddCaptured(ANode, AOuterLocals[mFound], mWritten);
  end;
end;

/// <summary>Index der äußeren Lokalen zu ANode; -1, wenn keine oder in der anonymen Methode deklariert.</summary>
function TSiteAnalysis.OuterIndex(ANode: TSyntaxNode; const AOuterLocals: TArray<TRoutineLocal>): Integer;
begin
  Result := TRoutineLocals.IndexOf(AOuterLocals, ANode.Name, ANode.StartOffset);
  if (Result >= 0) and TRoutineBody.Within(AOuterLocals[Result].Decl, FSite.Anonymous) then
  begin
    Result := -1;
  end;
end;

/// <summary>Nutzt AName eine lokale Routine (nur mit ARoutines) oder einen lokalen Typ der äußeren Routine?
/// </summary>
function TSiteAnalysis.OuterNameReason(const AName: string; ARoutines: Boolean): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex < FSite.Outer.ChildCount) do
  begin
    mChild := FSite.Outer[mIndex];
    if ARoutines and (mChild.Kind = TSyntaxKind.RoutineDecl) and SameText(mChild.Name, AName) then
    begin
      Result := cTexts[TEditingAnonymousMethodsText.UsesTheLocalRoutine].Text + mChild.Name;
    end
    else if (mChild.Kind = TSyntaxKind.TypeSection) and (IndexText(AName, TRoutineParts.ChildNames(mChild)) >= 0) then
    begin
      Result := cTexts[TEditingAnonymousMethodsText.UsesTheLocalType].Text + AName;
    end;
    Inc(mIndex);
  end;
end;

function TSiteAnalysis.TypeReferencesReason(AIdentifiers: TList<TSyntaxNode>): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex < AIdentifiers.Count) do
  begin
    Result := OuterNameReason(AIdentifiers[mIndex].Name, False);
    Inc(mIndex);
  end;
end;

/// <summary>Konstante der äußeren Routine wandert mit; geschrieben werden darf sie nicht.</summary>
function TSiteAnalysis.AddConstant(ANode: TSyntaxNode; const ALocal: TRoutineLocal; AWritten: Boolean): string;
var
  mLine: string;
begin
  Result := '';
  mLine := TRoutineBody.TextOf(FSite.Input.Text, ALocal.Decl);
  if AWritten then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.WritesTheConstant].Text + ANode.Name;
  end
  else if IndexText(mLine, FSite.ConstLines) < 0 then
  begin
    FSite.ConstLines := FSite.ConstLines + [mLine];
  end;
end;

/// <summary>Index von ALocal in FSite.Captured; FCount, wenn noch nicht erfasst.</summary>
function TSiteAnalysis.CapturedIndex(const ALocal: TRoutineLocal): Integer;
begin
  Result := 0;
  while (Result < FCount) and not ((FSite.Captured[Result].Local.Decl = ALocal.Decl) and
    SameText(FSite.Captured[Result].Local.Name, ALocal.Name)) do
  begin
    Inc(Result);
  end;
end;

procedure TSiteAnalysis.AddCaptured(ANode: TSyntaxNode; const ALocal: TRoutineLocal; AWritten: Boolean);
var
  mIndex: Integer;
begin
  mIndex := CapturedIndex(ALocal);
  if mIndex = FCount then
  begin
    Inc(FCount);
    FSite.Captured[mIndex] := Default(TAnonymousCaptured);
    FSite.Captured[mIndex].Local := ALocal;
    FSite.Captured[mIndex].TypeText := ALocal.TypeText;
    if (ALocal.TypeText = '') and Assigned(FSite.Input.Lookup.InlineType) then
    begin
      FSite.Captured[mIndex].TypeText := FSite.Input.Lookup.InlineType(ALocal);
    end;
  end;
  if AWritten then
  begin
    FSite.Captured[mIndex].Written := True;
  end;
  if TRoutineParts.InAnonymous(ANode, FSite.Anonymous) then
  begin
    FSite.Captured[mIndex].InNested := True;
  end;
end;

procedure TSiteAnalysis.ClassifyUse;
var
  mParent: TSyntaxNode;
begin
  FSite.Synchronous := False;
  FSite.CallName := '';
  mParent := FSite.Anonymous.Parent;
  if TAnonymousSyntax.IsArgument(FSite.Anonymous, mParent) then
  begin
    FSite.CallName := CalleeName(mParent);
    // TComparer<T>.Construct(…) direkt als Argument von Sort: läuft mit der Sortierung.
    FSite.Synchronous := MatchText(FSite.CallName, cSyncCalls) or (SameText(FSite.CallName, 'Construct') and
      TAnonymousSyntax.IsArgument(mParent, mParent.Parent) and MatchText(CalleeName(mParent.Parent), cSyncCalls));
  end;
end;

function TSiteAnalysis.ChooseForm: string;
begin
  FSite.FieldsReason := '';
  FSite.Form := TAnonymousForm.Direct;
  Result := '';
  if FSite.Captured = nil then
  begin
    Exit;
  end;
  Result := UnknownTypeReason;
  if Result <> '' then
  begin
    Exit;
  end;
  FSite.Form := TAnonymousForm.Forwarding;
  if not FSite.Synchronous and (FSite.Input.Capture = TDeferredCapture.Fields) then
  begin
    FSite.FieldsReason := FieldsProblem;
    if FSite.FieldsReason = '' then
    begin
      FSite.Form := TAnonymousForm.Fields;
    end;
  end;
  if FSite.Form = TAnonymousForm.Forwarding then
  begin
    Result := NestedReason;
  end;
end;

function TSiteAnalysis.UnknownTypeReason: string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex <= High(FSite.Captured)) do
  begin
    if FSite.Captured[mIndex].TypeText = '' then
    begin
      Result := cTexts[TEditingAnonymousMethodsText.TypeOfUnknown].Fmt([FSite.Captured[mIndex].Local.Name]);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Warum die eingestellte Form Fields nicht geht; '' wenn sie geht.</summary>
function TSiteAnalysis.FieldsProblem: string;
begin
  if not FSite.IsMethod or FSite.IsClass then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.OnlyInMethodsOfAn].Text;
  end
  else if AnyWritten(FSite.Captured) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.TheAnonymousMethodWritesCaptured].Text;
  end
  else if TRoutineBody.HostStatement(FSite.Anonymous, TRoutineBody.BodyOf(FSite.Outer)) = nil then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.NothingCanBeInsertedBefore].Text;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Eine verschachtelte anonyme Methode darf keine künftige var-Variable erfassen.</summary>
function TSiteAnalysis.NestedReason: string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 0;
  while (Result = '') and (mIndex <= High(FSite.Captured)) do
  begin
    if FSite.Captured[mIndex].Written and FSite.Captured[mIndex].InNested then
    begin
      Result := cTexts[TEditingAnonymousMethodsText.ANestedAnonymousMethodCaptures].Fmt([
        FSite.Captured[mIndex].Local.Name]);
    end;
    Inc(mIndex);
  end;
end;

function TSiteAnalysis.SuggestName: string;
var
  mParent: TSyntaxNode;
  mTaken: TArray<string>;
begin
  mParent := FSite.Anonymous.Parent;
  if (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent.ChildCount > 1) and
    (mParent[1] = FSite.Anonymous) then
  begin
    Result := HandlerName(mParent[0].Name);
  end
  else if mParent.Kind = TSyntaxKind.InlineVar then
  begin
    Result := HandlerName(Trim(mParent.Name.Split([','])[0]));
  end
  else if TAnonymousSyntax.IsArgument(FSite.Anonymous, mParent) then
  begin
    Result := ArgumentName;
  end
  else
  begin
    Result := '';
  end;
  if not IsValidName(Result) then
  begin
    Result := 'HandleAnonymous';
  end;
  mTaken := SiteTaken(FSite);
  Result := TRoutineParts.FreeName(Result, mTaken);
  while SiteNameTaken(FSite, Result) do
  begin
    Result := TRoutineParts.FreeName(Result, mTaken + [Result]);
  end;
end;

/// <summary>Name aus dem Aufruf, dem die anonyme Methode als Argument dient; '' ohne.</summary>
function TSiteAnalysis.ArgumentName: string;
var
  mCall: string;
begin
  mCall := FSite.CallName;
  // Vergleich zweier Werte gleichen Typs: CompareBy + erstes verglichenes Feld.
  if TRoutineParts.IsFunction(FSite.Anonymous) and (Length(FSite.Parameters) = 2) and
    SameText(FSite.Parameters[0].Rest, FSite.Parameters[1].Rest) then
  begin
    Result := CompareName;
  end
  else if SameText(mCall, 'ForEach') then
  begin
    Result := 'ProcessItem';
  end
  else if SameText(mCall, 'For') then
  begin
    Result := 'ProcessIndex';
  end
  else if MatchText(mCall, cMainThreadCalls) then
  begin
    Result := 'UpdateInMainThread';
  end
  else if MatchText(mCall, cBackgroundCalls) then
  begin
    Result := 'RunInBackground';
  end
  else if mCall <> '' then
  begin
    Result := 'Handle' + Capitalized(mCall);
  end
  else
  begin
    Result := '';
  end;
end;

function TSiteAnalysis.CompareName: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mField: string;
  mIndex: Integer;
begin
  mField := '';
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(TRoutineBody.BodyOf(FSite.Anonymous), TSyntaxKind.MemberAccess, mNodes);
    mIndex := 0;
    while (mField = '') and (mIndex < mNodes.Count) do
    begin
      mNode := mNodes[mIndex];
      if (mNode.ChildCount > 0) and (mNode[0].Kind = TSyntaxKind.Identifier) and
        SameText(mNode[0].Name, FSite.Parameters[0].Name) then
      begin
        mField := mNode.Name;
      end;
      Inc(mIndex);
    end;
  finally
    mNodes.Free;
  end;
  Result := 'CompareBy' + Capitalized(mField);
  if mField = '' then
  begin
    Result := 'Compare';
  end;
end;

{ TSiteBuilder }

constructor TSiteBuilder.Create(const ASite: TAnonymousSite; const AName: string);
begin
  inherited Create;
  FSite := ASite;
  FName := AName;
  FLineBreak := TTextLines.LineBreakOf(ASite.Input.Text);
end;

function TSiteBuilder.Build(ACheckName: Boolean; out AResult: TAnonymousResult; out AReason: string): Boolean;
var
  mMoved: string;
begin
  AResult := Default(TAnonymousResult);
  AReason := '';
  if ACheckName then
  begin
    AReason := NameReason;
  end;
  FParameters := FSite.Parameters;
  if FSite.Form = TAnonymousForm.Forwarding then
  begin
    AddForwardParameters;
  end;
  if FSite.Form = TAnonymousForm.Fields then
  begin
    NameFields;
  end;
  if (AReason <> '') or not MethodText(mMoved, AReason) then
  begin
    Exit(False);
  end;
  FEdits := nil;
  // Felder vor der Anweisung füllen.
  if FSite.Form = TAnonymousForm.Fields then
  begin
    AddFieldAssignments;
  end;
  FEdits := FEdits + [TTextEdit.Create(TTextRange.Create(FSite.Anonymous.StartPos, FSite.Anonymous.EndPos),
    CallSite)];
  if FSite.IsMethod then
  begin
    AReason := AddMethodEdits(mMoved);
  end
  else
  begin
    AddRoutineEdit(mMoved);
  end;
  Result := AReason = '';
  if Result then
  begin
    AResult.Edits := FEdits;
    AResult.Form := FSite.Form;
    AResult.Preview := Preview;
    AResult.Warnings := Warnings;
  end;
end;

function TSiteBuilder.NameReason: string;
begin
  if not IsValidName(FName) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.IsNotAValidName].Fmt([FName]);
  end
  else if SiteNameTaken(FSite, FName) then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.IsAlreadyTaken].Fmt([FName]);
  end
  else
  begin
    Result := '';
  end;
end;

procedure TSiteBuilder.AddForwardParameters;
var
  mIndex: Integer;
  mParameter: TParameterText;
begin
  for mIndex := 0 to High(FSite.Captured) do
  begin
    mParameter := Default(TParameterText);
    mParameter.Name := FSite.Captured[mIndex].Local.Name;
    mParameter.Rest := ': ' + FSite.Captured[mIndex].TypeText;
    mParameter.Modifier := ModifierOf(FSite.Captured[mIndex]);
    FParameters := FParameters + [mParameter];
  end;
end;

/// <summary>const bei Strings, Records und Interfaces; ein const-Parameter der äußeren Routine bleibt const.
/// </summary>
function TSiteBuilder.ReadsAsConst(const ACaptured: TAnonymousCaptured): Boolean;
var
  mLookup: TAnonymousLookup;
begin
  mLookup := FSite.Input.Lookup;
  Result := TCreateMethod.WantsConst(ACaptured.TypeText, False, False) or (Assigned(mLookup.ConstType) and
    mLookup.ConstType(ACaptured.TypeText, FSite.Anonymous.StartOffset)) or
    ((ACaptured.Local.Kind = TRoutineLocalKind.Parameter) and StartsText('const ',
    TRoutineBody.TextOf(FSite.Input.Text, ACaptured.Local.Decl)));
end;

function TSiteBuilder.ModifierOf(const ACaptured: TAnonymousCaptured): string;
begin
  if ACaptured.Written then
  begin
    Result := 'var';
  end
  else if ReadsAsConst(ACaptured) then
  begin
    Result := 'const';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Felder: F + Name ohne L-Präfix, eindeutig in der Klasse.</summary>
procedure TSiteBuilder.NameFields;
var
  mTaken: TArray<string>;
  mIndex: Integer;
begin
  mTaken := SiteTaken(FSite) + [FName];
  for mIndex := 0 to High(FSite.Captured) do
  begin
    FSite.Captured[mIndex].Field := FieldName(FSite.Captured[mIndex].Local.Name, mTaken);
    mTaken := mTaken + [FSite.Captured[mIndex].Field];
  end;
end;

function TSiteBuilder.FieldTaken(const AField: string): Boolean;
begin
  Result := (Assigned(FSite.Input.Lookup.MemberExists) and FSite.Input.Lookup.MemberExists(FSite.ClassName, AField,
    FSite.Anonymous.StartOffset)) or FSite.Cache.Declares(FSite.Anonymous, AField, MaxInt);
end;

function TSiteBuilder.FieldName(const ALocalName: string; const ATaken: TArray<string>): string;
begin
  Result := TRoutineParts.FreeName(TPromoteVariable.FieldName(ALocalName), ATaken);
  while FieldTaken(Result) do
  begin
    Result := TRoutineParts.FreeName(Result, ATaken + [Result]);
  end;
end;

/// <summary>Feld zum erfassten Namen ANode; '' wenn ANode nichts Erfasstes meint.</summary>
function TSiteBuilder.CapturedField(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  if TRoutineParts.Shadowed(FSite.Cache, ANode, FSite.Anonymous, ANode.Name, True) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FSite.Captured) do
  begin
    if SameText(ANode.Name, FSite.Captured[mIndex].Local.Name) then
    begin
      Result := FSite.Captured[mIndex].Field;
    end;
  end;
end;

/// <summary>Form Fields: Erfasste Namen im Rumpf heißen wie die Felder.</summary>
function TSiteBuilder.FieldEdits: TArray<TOffsetEdit>;
var
  mIdentifiers: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mField: string;
begin
  Result := nil;
  if FSite.Form <> TAnonymousForm.Fields then
  begin
    Exit;
  end;
  mIdentifiers := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(FSite.Anonymous, TSyntaxKind.Identifier, mIdentifiers);
    for mNode in mIdentifiers do
    begin
      mField := CapturedField(mNode);
      if mField <> '' then
      begin
        Result := Result + [TOffsetEdit.Create(mNode.StartOffset, mNode.EndOffset, mField)];
      end;
    end;
  finally
    mIdentifiers.Free;
  end;
end;

/// <summary>begin X; end in einer Zeile: in Zeilen zerlegt. False, wenn begin oder end fehlt.</summary>
function TSiteBuilder.OneLineBody(const AEdits: TArray<TOffsetEdit>; const AIndent: string;
  out ABody: string): Boolean;
var
  mText, mInner, mBefore: string;
  mBlock: TSyntaxNode;
  mBeginToken, mEndToken, mInnerStart, mInnerStop, mStart: Integer;
begin
  ABody := '';
  mText := FSite.Input.Text;
  mBlock := TRoutineBody.BodyOf(FSite.Anonymous);
  mBeginToken := TRoutineBody.TokenAt(FSite.Tokens, mBlock.StartOffset);
  mEndToken := PreviousCode(FSite.Tokens, TRoutineBody.TokenAt(FSite.Tokens, mBlock.EndOffset));
  Result := (mBeginToken <= High(FSite.Tokens)) and FSite.Tokens[mBeginToken].IsKeyword('begin') and
    (mEndToken >= 0) and FSite.Tokens[mEndToken].IsKeyword('end');
  if not Result then
  begin
    Exit;
  end;
  mInnerStart := FSite.Tokens[mBeginToken].Offset + Length(FSite.Tokens[mBeginToken].Text);
  mInnerStop := FSite.Tokens[mEndToken].Offset;
  mInner := Trim(TRoutineParts.ApplyEdits(Copy(mText, mInnerStart + 1, mInnerStop - mInnerStart), mInnerStart,
    AEdits));
  mStart := HeadEnd(FSite.Anonymous);
  mBefore := Trim(Copy(mText, mStart + 1, mBlock.StartOffset - mStart));
  if mBefore <> '' then
  begin
    ABody := TRoutineBody.Reindent(mBefore, TTextLines.IndentOf(mText, FSite.Anonymous.StartPos.Line), AIndent,
      FLineBreak) + FLineBreak;
  end;
  ABody := ABody + AIndent + 'begin' + FLineBreak;
  if mInner <> '' then
  begin
    ABody := ABody + AIndent + TRoutineBody.IndentUnit(FSite.Input.Style) + mInner + FLineBreak;
  end;
  ABody := ABody + AIndent + 'end;';
end;

function TSiteBuilder.MultiLineBody(const AEdits: TArray<TOffsetEdit>; const AIndent: string): string;
var
  mText: string;
  mStart: Integer;
begin
  mText := FSite.Input.Text;
  mStart := HeadEnd(FSite.Anonymous);
  Result := TRoutineParts.ApplyEdits(Copy(mText, mStart + 1, FSite.Anonymous.EndOffset - mStart), mStart, AEdits);
  Result := TRoutineBody.Reindent(TrimLeft(Result), TTextLines.IndentOf(mText,
    TRoutineBody.BodyOf(FSite.Anonymous).EndPos.Line), AIndent, FLineBreak) + ';';
end;

/// <summary>Mitwandernde Konstanten als const-Abschnitt; '' ohne.</summary>
function TSiteBuilder.ConstBlock(const AIndent: string): string;
var
  mLine: string;
begin
  Result := '';
  if FSite.ConstLines = nil then
  begin
    Exit;
  end;
  Result := AIndent + 'const' + FLineBreak;
  for mLine in FSite.ConstLines do
  begin
    Result := Result + AIndent + TRoutineBody.IndentUnit(FSite.Input.Style) + mLine + FLineBreak;
  end;
end;

/// <summary>Text der neuen Methode bzw. Routine: Kopf, Konstanten, Rumpf.</summary>
function TSiteBuilder.MethodText(out AText: string; out AReason: string): Boolean;
var
  mIndent, mBody: string;
  mEdits: TArray<TOffsetEdit>;
  mBlock: TSyntaxNode;
begin
  AText := '';
  AReason := '';
  mIndent := TTextLines.IndentOf(FSite.Input.Text, FSite.Outer.StartPos.Line);
  mEdits := FieldEdits;
  mBlock := TRoutineBody.BodyOf(FSite.Anonymous);
  Result := True;
  if mBlock.StartPos.Line = mBlock.EndPos.Line then
  begin
    Result := OneLineBody(mEdits, mIndent, mBody);
  end
  else
  begin
    mBody := MultiLineBody(mEdits, mIndent);
  end;
  if Result then
  begin
    AText := mIndent + TRoutineParts.HeadText(FSite.Input.Text, FSite.Anonymous, Qualified(FSite, FName),
      FParameters, FSite.IsClass) + FLineBreak + ConstBlock(mIndent) + mBody;
  end
  else
  begin
    AReason := cTexts[TEditingAnonymousMethodsText.BodyNotReadable].Text;
  end;
end;

/// <summary>Argumente der Weiterleitung: eigene Parameter, dann die erfassten Variablen.</summary>
function TSiteBuilder.ArgumentList: string;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  mNames := nil;
  for mIndex := 0 to High(FSite.Parameters) do
  begin
    mNames := mNames + [FSite.Parameters[mIndex].Name];
  end;
  Result := Joined(mNames + CapturedNames(FSite.Captured), ', ');
end;

/// <summary>Was an der Stelle der anonymen Methode steht: der Name oder die kurze Weiterleitung.</summary>
function TSiteBuilder.CallSite: string;
var
  mCall, mHead, mIndent: string;
begin
  if FSite.Form <> TAnonymousForm.Forwarding then
  begin
    Exit(FName);
  end;
  mCall := FName + '(' + ArgumentList + ');';
  if TRoutineParts.IsFunction(FSite.Anonymous) then
  begin
    mCall := 'Result := ' + mCall;
  end;
  mHead := TrimRight(Copy(FSite.Input.Text, FSite.Anonymous.StartOffset + 1, HeadEnd(FSite.Anonymous) -
    FSite.Anonymous.StartOffset));
  if FSite.Anonymous.StartPos.Line = FSite.Anonymous.EndPos.Line then
  begin
    Exit(mHead + ' begin ' + mCall + ' end');
  end;
  mIndent := TTextLines.IndentOf(FSite.Input.Text, TRoutineBody.BodyOf(FSite.Anonymous).EndPos.Line);
  Result := mHead + FLineBreak + mIndent + 'begin' + FLineBreak + mIndent +
    TRoutineBody.IndentUnit(FSite.Input.Style) + mCall + FLineBreak + mIndent + 'end';
end;

/// <summary>Form Fields: Werte vor der Anweisung in die Felder kopieren.</summary>
procedure TSiteBuilder.AddFieldAssignments;
var
  mHost: TSyntaxNode;
  mAssignments, mIndent: string;
  mIndex: Integer;
begin
  mHost := TRoutineBody.HostStatement(FSite.Anonymous, TRoutineBody.BodyOf(FSite.Outer));
  mIndent := TTextLines.IndentOf(FSite.Input.Text, mHost.StartPos.Line);
  mAssignments := '';
  for mIndex := 0 to High(FSite.Captured) do
  begin
    if mAssignments <> '' then
    begin
      mAssignments := mAssignments + FLineBreak + mIndent;
    end;
    mAssignments := mAssignments + FSite.Captured[mIndex].Field + ' := ' + FSite.Captured[mIndex].Local.Name + ';';
  end;
  FEdits := FEdits + [TRoutineBody.InsertBefore(FSite.Input.Text, mHost, mAssignments)];
end;

/// <summary>Form Fields: Felder deklarieren; ohne private-Abschnitt vor ADeclaration im neuen Abschnitt.</summary>
function TSiteBuilder.AddFieldsDeclaration(var ADeclaration: string): string;
var
  mFields: string;
  mIndex: Integer;
  mEdit: TTextEdit;
begin
  Result := '';
  mFields := '';
  for mIndex := 0 to High(FSite.Captured) do
  begin
    if mFields <> '' then
    begin
      mFields := mFields + ' ';
    end;
    mFields := mFields + FSite.Captured[mIndex].Field + ': ' + FSite.Captured[mIndex].TypeText + ';';
  end;
  if not HasPrivateSection(FSite.TypeBody) then
  begin
    // Neuer Abschnitt: Felder und Methode in einem, Felder zuerst (E2169).
    ADeclaration := mFields + FLineBreak + TTextLines.IndentOf(FSite.Input.Text, FSite.TypeBody.EndPos.Line) +
      TRoutineBody.IndentUnit(FSite.Input.Style) + ADeclaration;
  end
  else if TRoutineBody.FieldDeclaration(FSite.Input.Text, FSite.Input.Tree, FSite.TypeBody, mFields,
    FSite.Input.Style, mEdit) then
  begin
    FEdits := FEdits + [mEdit];
  end
  else
  begin
    Result := cTexts[TEditingAnonymousMethodsText.ClassDeclarationCannotBeExtended].Text;
  end;
end;

/// <summary>Methode hinter der äußeren einfügen und im private-Abschnitt deklarieren.</summary>
function TSiteBuilder.AddMethodEdits(const AMoved: string): string;
var
  mInsertLine: Integer;
  mMoved, mDeclaration: string;
  mEdit: TTextEdit;
begin
  mMoved := AMoved;
  mInsertLine := FSite.Outer.EndPos.Line + 1;
  // Leerzeile davor und, wenn direkt etwas folgt, auch danach.
  if not TRoutineParts.LineIsBlank(TTextLines.SplitLines(FSite.Input.Text), mInsertLine) then
  begin
    mMoved := mMoved + FLineBreak;
  end;
  FEdits := FEdits + [TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0), FLineBreak + mMoved +
    FLineBreak)];
  mDeclaration := TRoutineParts.HeadText(FSite.Input.Text, FSite.Anonymous, FName, FParameters, FSite.IsClass);
  if FSite.IsStatic then
  begin
    mDeclaration := mDeclaration + ' static;';
  end;
  Result := '';
  if FSite.Form = TAnonymousForm.Fields then
  begin
    Result := AddFieldsDeclaration(mDeclaration);
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  if TRoutineBody.MemberDeclaration(FSite.Input.Text, FSite.Input.Tree, FSite.TypeBody,
    TMemberEntry.Create('private', mDeclaration), FSite.Input.Style, mEdit) then
  begin
    FEdits := FEdits + [mEdit];
  end
  else
  begin
    Result := cTexts[TEditingAnonymousMethodsText.ClassDeclarationCannotBeExtended].Text;
  end;
end;

/// <summary>Routine der Unit vor der äußeren Routine einfügen.</summary>
procedure TSiteBuilder.AddRoutineEdit(const AMoved: string);
var
  mInsertLine: Integer;
begin
  mInsertLine := TRoutineBody.RoutineInsertLine(FSite.Input.Text, FSite.Outer);
  FEdits := FEdits + [TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0), AMoved + FLineBreak +
    FLineBreak)];
end;

function TSiteBuilder.ForwardingExplanation(const ANames: string): string;
begin
  if FSite.Synchronous then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.RunsDuringTheCapturedVariables].Fmt([FSite.CallName, ANames, FName]);
  end
  else
  begin
    Result := cTexts[TEditingAnonymousMethodsText.MayRunLaterANamed].Fmt([ANames, FName]);
  end;
  if FSite.FieldsReason <> '' then
  begin
    Result := Result + FLineBreak + cTexts[TEditingAnonymousMethodsText.NotPossibleAsFieldsHere].Fmt([
      FSite.FieldsReason]);
  end;
end;

/// <summary>Erklärung der Form für die Vorschau.</summary>
function TSiteBuilder.FormExplanation: string;
var
  mNames: string;
begin
  mNames := Joined(CapturedNames(FSite.Captured), ', ');
  case FSite.Form of
    TAnonymousForm.Direct:
      Result := cTexts[TEditingAnonymousMethodsText.CapturesNoVariablesTheSite].Fmt([FName]);
    TAnonymousForm.Forwarding:
      Result := ForwardingExplanation(mNames);
    TAnonymousForm.Fields:
      Result := cTexts[TEditingAnonymousMethodsText.RunsLaterTheValuesOf].Fmt([mNames, FName]);
  else
    Result := '';
  end;
end;

/// <summary>Vorschau: Kopf und Form.</summary>
function TSiteBuilder.Preview: string;
begin
  if FSite.IsMethod then
  begin
    Result := cTexts[TEditingAnonymousMethodsText.NewMethod].Text;
  end
  else
  begin
    Result := cTexts[TEditingAnonymousMethodsText.NewRoutine].Text;
  end;
  Result := Result + TRoutineParts.HeadText(FSite.Input.Text, FSite.Anonymous, Qualified(FSite, FName), FParameters,
    FSite.IsClass) + FLineBreak + FormExplanation;
end;

function TSiteBuilder.Warnings: TArray<string>;
begin
  Result := nil;
  if FSite.Form = TAnonymousForm.Fields then
  begin
    Result := TArray<string>.Create(cTexts[TEditingAnonymousMethodsText.ReadsTheValuesFromFields].Fmt([FName,
      Joined(CapturedNames(FSite.Captured), ', ')]));
  end;
end;

{ TAnonymousMethods }

class function TAnonymousMethods.ToMethodTitle: string;
begin
  Result := cTexts[TEditingAnonymousMethodsText.ToMethodTitle].Text;
end;

class function TAnonymousMethods.ToRoutineTitle: string;
begin
  Result := cTexts[TEditingAnonymousMethodsText.ToRoutineTitle].Text;
end;

class function TAnonymousMethods.EmbedTitle: string;
begin
  Result := Atlas.Common.Editing.AnonymousMethods.Shared.EmbedTitle;
end;

class function TAnonymousMethods.KindOfTypeText(const ATypeText: string): TProcTypeKind;
var
  mName: string;
begin
  mName := Trim(ATypeText);
  if StartsText('reference ', mName) then
  begin
    Result := TProcTypeKind.Reference;
  end
  else if ContainsText(mName, ' of object') then
  begin
    Result := TProcTypeKind.MethodPointer;
  end
  else if StartsText('procedure', mName) or StartsText('function', mName) then
  begin
    Result := TProcTypeKind.Plain;
  end
  else
  begin
    Result := KindOfTypeName(mName);
  end;
end;

/// <summary>Baut die Umwandlung der geprüften Stelle mit dem Namen AName.</summary>
function BuildSite(AAnalysis: TSiteAnalysis; const AName: string; ACheckName: Boolean;
  out AResult: TAnonymousResult; out AReason: string): Boolean;
var
  mBuilder: TSiteBuilder;
begin
  mBuilder := TSiteBuilder.Create(AAnalysis.Site, AName);
  try
    Result := mBuilder.Build(ACheckName, AResult, AReason);
  finally
    mBuilder.Free;
  end;
end;

class function TAnonymousMethods.Target(const AInput: TAnonymousInput; out ATarget: TAnonymousTarget;
  out AReason: string): Boolean;
var
  mAnalysis: TSiteAnalysis;
  mProbe: TAnonymousResult;
begin
  ATarget := Default(TAnonymousTarget);
  mAnalysis := TSiteAnalysis.Create(AInput);
  try
    Result := mAnalysis.Analyze(AReason) and BuildSite(mAnalysis, mAnalysis.Site.Suggested, False, mProbe,
      AReason);
    if Result then
    begin
      ATarget.IsMethod := mAnalysis.Site.IsMethod;
      ATarget.Suggested := mAnalysis.Site.Suggested;
      ATarget.Form := mAnalysis.Site.Form;
    end;
  finally
    mAnalysis.Free;
  end;
end;

class function TAnonymousMethods.Execute(const AInput: TAnonymousInput; const AName: string;
  out AResult: TAnonymousResult; out AReason: string): Boolean;
var
  mAnalysis: TSiteAnalysis;
begin
  AResult := Default(TAnonymousResult);
  mAnalysis := TSiteAnalysis.Create(AInput);
  try
    Result := mAnalysis.Analyze(AReason) and BuildSite(mAnalysis, Trim(AName), True, AResult, AReason);
  finally
    mAnalysis.Free;
  end;
end;

class function TAnonymousMethods.Embed(const AInput: TAnonymousInput; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  mEmbedding: TAnonymousEmbedding;
begin
  mEmbedding := TAnonymousEmbedding.Create(AInput);
  try
    Result := mEmbedding.Run(AAction, AReason);
  finally
    mEmbedding.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.AnonymousMethods', cTexts);

end.
