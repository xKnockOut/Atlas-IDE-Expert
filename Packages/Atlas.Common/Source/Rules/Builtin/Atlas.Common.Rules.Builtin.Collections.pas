unit Atlas.Common.Rules.Builtin.Collections;

// Regeln für Listen und andere Sammlungen (#909, Gruppe Stil und Metriken):
//   legacy-tlist        Ungenerische TList (System.Classes) bzw. TObjectList
//                       (System.Contnrs) mit Cast beim Lesen (#981, Standard aus).
//   legacy-stack-queue  Ungenerische TStack, TQueue, TObjectStack bzw.
//                       TObjectQueue (System.Contnrs) mit Cast beim Lesen über
//                       Pop oder Peek (#1106, Standard aus).
//
// TLegacyCollections.Reads sucht Casts T(Liste[I]), T(Liste.Items[I]),
// T(Liste.First), Liste[I] as T usw. im Syntaxbaum und löst Sammlung und
// Zieltyp über TNameResolver auf. Gemeldet wird nur, wenn der Typ der
// Sammlung sicher die ungenerische Klasse aus der RTL ist und der Zieltyp ein
// bekannter Typ (kein Pointer). Je Sammlung gibt es einen Treffer: an der
// Deklaration, wenn sie in der Datei steht, sonst am ersten Cast.
//
// Schnellkorrektur (#1105): TLegacyCollections.ConversionFix wandelt die
// Sammlung über Editing.GenericLists in ihr generisches Gegenstück um
// (Deklaration, Create, Casts, uses in einem Schritt). Steht die Deklaration
// in einer anderen Unit oder ist die Sammlung außerhalb der Unit sichtbar,
// liest sie die betroffenen Units über TRuleContext.ProjectFiles; solche
// Korrekturen ändern mehrere Dateien und sind nie Safe. Geht es nicht, nennt
// der Befund-Hover den Grund (TRuleFinding.Details). TLegacyCollectionRule
// ist die gemeinsame Grundlage für legacy-tlist und die Stapel und
// Warteschlangen aus #1106.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cLegacyTListRuleId = 'legacy-tlist';
  cLegacyStackQueueRuleId = 'legacy-stack-queue';

type
  /// <summary>Ungenerische Sammlung der RTL: Unit (mit und ohne Namespace) und Klassenname.</summary>
  TLegacyCollectionType = record
    UnitName: string;
    ShortUnitName: string;
    TypeName: string;
    constructor Create(const AUnitName, AShortUnitName, ATypeName: string);
  end;

  /// <summary>Ein Lesezugriff mit Cast auf eine ungenerische Sammlung.</summary>
  TLegacyCollectionRead = record
    /// <summary>Der ganze Cast: T(Liste[I]) bzw. Liste[I] as T.</summary>
    Cast: TSyntaxNode;
    /// <summary>Ausdruck der Sammlung, z. B. FPositionen oder Self.FPositionen.</summary>
    Collection: TSyntaxNode;
    /// <summary>Deklaration der Sammlung (Variable, Feld, Property, Parameter).</summary>
    Symbol: TResolvedSymbol;
    /// <summary>Klasse der Sammlung, z. B. System.Classes.TList.</summary>
    CollectionType: TResolvedSymbol;
    /// <summary>Zieltyp des Casts.</summary>
    CastType: TResolvedSymbol;
    /// <summary>Schlüssel der Deklaration: gleiche Sammlung, gleicher Schlüssel.</summary>
    function Key: string;
  end;

  TLegacyCollections = class
  public
    /// <summary>Alle Lesezugriffe mit Cast auf Sammlungen der Typen ATypes. AMembers sind die Methoden und
    /// Properties, die ein Element liefern (First, Last, Pop …); AIndexed: auch Liste[I] und Liste.Items[I].
    /// AResolver muss auf ATree gepinnt sein.</summary>
    class function Reads(ATree: TSyntaxTree; const AFileName: string; AResolver: TNameResolver;
      const ATypes: TArray<TLegacyCollectionType>; const AMembers: TArray<string>;
      AIndexed: Boolean): TArray<TLegacyCollectionRead>; static;
    /// <summary>Steht die Deklaration ASymbol in der Datei AFileName?</summary>
    class function DeclaredIn(const ASymbol: TResolvedSymbol; const AFileName: string): Boolean; static;
    /// <summary>Korrektur "In TList&lt;T&gt; umwandeln" für die Sammlung von ARead (#1105); False mit dem Grund
    /// in AReason, wenn sie nicht sicher möglich ist.</summary>
    class function ConversionFix(const AContext: TRuleContext; const AFileName: string;
      const ARead: TLegacyCollectionRead; AResolver: TNameResolver; out AFix: TRuleFix;
      out AReason: string): Boolean; static;
  end;

  /// <summary>Gemeinsame Prüfung ungenerischer Sammlungen mit Cast (#981, #1106): je Sammlung ein Treffer mit
  /// allen Zieltypen, dazu die Umwandlung als Korrektur bzw. der Grund, warum es keine gibt (#1105).
  /// Nachfahren nennen Typen, Lesemethoden und Meldung.</summary>
  TLegacyCollectionRule = class(TInterfacedObject, IRule)
  protected
    /// <summary>Gesuchte Klassen, z. B. TList aus System.Classes.</summary>
    function CollectionTypes: TArray<TLegacyCollectionType>; virtual; abstract;
    /// <summary>Methoden und Properties, die ein Element liefern (First, Pop …).</summary>
    function ReadMembers: TArray<string>; virtual; abstract;
    /// <summary>Auch Liste[I] und Liste.Items[I]?</summary>
    function IndexedReads: Boolean; virtual; abstract;
    /// <summary>Meldung für eine Sammlung der Klasse ACollectionType mit den Zieltypen ACastTypes.</summary>
    function FindingMessage(const ACollectionType: string; const ACastTypes: TArray<string>): string;
      virtual; abstract;
  public
    function Descriptor: TRuleDescriptor; virtual; abstract;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  private
    /// <summary>Ein Treffer für die Sammlung von AFirst mit den Zieltypen ACastTypes, dazu die Umwandlung bzw. der
    /// Grund, warum es keine gibt.</summary>
    procedure ReportCollection(const AContext: TRuleContext; const AReport: IRuleReport; const AFileName: string;
      const AFirst: TLegacyCollectionRead; const ACastTypes: TArray<string>; AResolver: TNameResolver);
  end;

  TLegacyTListRule = class(TLegacyCollectionRule)
  protected
    function CollectionTypes: TArray<TLegacyCollectionType>; override;
    function ReadMembers: TArray<string>; override;
    function IndexedReads: Boolean; override;
    function FindingMessage(const ACollectionType: string; const ACastTypes: TArray<string>): string; override;
  public
    function Descriptor: TRuleDescriptor; override;
  end;

  /// <summary>Stapel und Warteschlangen aus System.Contnrs (#1106). Die Korrektur benennt bei Warteschlangen
  /// Push/Pop in Enqueue/Dequeue um und erzeugt TObjectStack&lt;T&gt;/TObjectQueue&lt;T&gt; mit Create(False), weil
  /// die Contnrs-Klassen ihre Objekte nicht besitzen (Editing.GenericLists).</summary>
  TLegacyStackQueueRule = class(TLegacyCollectionRule)
  protected
    function CollectionTypes: TArray<TLegacyCollectionType>; override;
    function ReadMembers: TArray<string>; override;
    function IndexedReads: Boolean; override;
    function FindingMessage(const ACollectionType: string; const ACastTypes: TArray<string>): string; override;
  public
    function Descriptor: TRuleDescriptor; override;
  end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCollectionsText = (VisibleNoProject, VisibleNotReady, NotReadable, DeclaredNoProject, DeclaredNotLoaded,
    DeclaredNoGroup, NotFieldOrVariable, NoGeneric, NoQuickFix, ListTitle, ListCast, ListCasts, StackTitle, NonGeneric,
    GenericStack, NonGenericFem, GenericQueue, StackCast, StackCasts);

const
  cTexts: array[TCollectionsText] of TAtlasText = (
    (De: '%s ist auch in anderen Units sichtbar, und ohne geladenes Projekt lassen sie sich nicht prüfen';
     En: '%s is also visible in other units, and they cannot be checked without a loaded project'),
    (De: '%s ist auch in anderen Units sichtbar, die sich noch nicht prüfen lassen (%s)';
     En: '%s is also visible in other units that cannot be checked yet (%s)'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: '%s ist in %s deklariert, und ohne geladenes Projekt lässt sich die Unit nicht ändern';
     En: '%s is declared in %s, and the unit cannot be changed without a loaded project'),
    (De: '%s ist in %s deklariert, und das Projekt ist noch nicht vollständig geladen (%s)';
     En: '%s is declared in %s, and the project is not completely loaded yet (%s)'),
    (De: '%s ist in %s deklariert, die zu keinem Projekt der Gruppe gehört';
     En: '%s is declared in %s, which belongs to no project of the group'),
    (De: 'Die Deklaration von %s ist kein Feld und keine Variable';
     En: 'The declaration of %s is neither a field nor a variable'),
    (De: 'Für %s gibt es kein generisches Gegenstück'; En: 'There is no generic counterpart for %s'),
    (De: 'Keine Schnellkorrektur: '; En: 'No quick fix: '),
    (De: 'Ungenerische Liste mit Cast'; En: 'Non-generic list with cast'),
    (De: 'Ungenerische %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.';
     En: 'Non-generic %s with cast on read; %s<%s> checks the type at compile time.'),
    (De: 'Ungenerische %s mit Casts auf %s beim Lesen; eine generische Liste prüft den Typ beim Übersetzen.';
     En: 'Non-generic %s with casts to %s on read; a generic list checks the type at compile time.'),
    (De: 'Ungenerischer Stapel oder ungenerische Warteschlange mit Cast'; En: 'Non-generic stack or queue with cast'),
    (De: 'Ungenerischer'; En: 'Non-generic'),
    (De: 'ein generischer Stapel'; En: 'a generic stack'),
    (De: 'Ungenerische'; En: 'Non-generic'),
    (De: 'eine generische Warteschlange'; En: 'a generic queue'),
    (De: '%s %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.';
     En: '%s %s with cast on read; %s<%s> checks the type at compile time.'),
    (De: '%s %s mit Casts auf %s beim Lesen; %s prüft den Typ beim Übersetzen.';
     En: '%s %s with casts to %s on read; %s checks the type at compile time.'));

{$SCOPEDENUMS OFF}

{ TLegacyCollectionType }

constructor TLegacyCollectionType.Create(const AUnitName, AShortUnitName, ATypeName: string);
begin
  UnitName := AUnitName;
  ShortUnitName := AShortUnitName;
  TypeName := ATypeName;
end;

{ TLegacyCollectionRead }

function TLegacyCollectionRead.Key: string;
begin
  Result := LowerCase(Symbol.UnitName + '|' + Symbol.FileName + '|' + Symbol.Container + '|' + Symbol.Name) + '|' +
    IntToStr(Symbol.SelectionRange.StartPos.Line) + ':' + IntToStr(Symbol.SelectionRange.StartPos.Character);
end;

{ TLegacyCollections }

/// <summary>Ausdruck ohne umschließende Klammern.</summary>
function Unparenthesized(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

function IsMember(const AName: string; const AMembers: TArray<string>): Boolean;
var
  mMember: string;
begin
  Result := False;
  for mMember in AMembers do
  begin
    if SameText(mMember, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TLegacyCollections.DeclaredIn(const ASymbol: TResolvedSymbol; const AFileName: string): Boolean;
begin
  Result := (ASymbol.Kind = TResolvedKind.Local) or
    ((ASymbol.Kind = TResolvedKind.Symbol) and SameText(ASymbol.FileName, AFileName));
end;

class function TLegacyCollections.Reads(ATree: TSyntaxTree; const AFileName: string; AResolver: TNameResolver;
  const ATypes: TArray<TLegacyCollectionType>; const AMembers: TArray<string>;
  AIndexed: Boolean): TArray<TLegacyCollectionRead>;
var
  mFound: TList<TLegacyCollectionRead>;

  /// <summary>Ist ANode sicher eine Sammlung der gesuchten Typen? Dann Deklaration und Typ.</summary>
  function IsLegacyCollection(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    mTypeFound: Boolean;
    mWanted: TLegacyCollectionType;
  begin
    Result := False;
    if (ANode = nil) or not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess,
      TSyntaxKind.IndexAccess, TSyntaxKind.Call]) then
    begin
      Exit;
    end;
    if not AResolver.NodeType(ATree, AFileName, ANode, ASymbol, AType, mTypeFound) or not mTypeFound or
      ASymbol.IsType or not AType.IsType then
    begin
      Exit;
    end;
    if (AType.TypeParams <> '') or (Pos('<', ASymbol.TypeName) > 0) then
    begin
      Exit;
    end;
    for mWanted in ATypes do
    begin
      Result := Result or SameText(AType.Name, mWanted.TypeName) and (SameText(AType.UnitName, mWanted.UnitName) or
        SameText(AType.UnitName, mWanted.ShortUnitName));
    end;
  end;

  /// <summary>Liste[I], Liste.Items[I], Objekt.Liste[I].</summary>
  function IndexedRead(AValue: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol,
    AType: TResolvedSymbol): Boolean;
  var
    mBase: TSyntaxNode;
  begin
    Result := False;
    ACollection := nil;
    if not AIndexed or (AValue.ChildCount <> 2) then
    begin
      Exit;
    end;
    mBase := AValue[0];
    if (mBase.Kind = TSyntaxKind.MemberAccess) and SameText(mBase.Name, 'Items') and (mBase.ChildCount = 1) and
      IsLegacyCollection(mBase[0], ASymbol, AType) then
    begin
      ACollection := mBase[0];
    end
    else if IsLegacyCollection(mBase, ASymbol, AType) then
    begin
      ACollection := mBase;
    end;
    Result := ACollection <> nil;
  end;

  /// <summary>Liest der Zugriff AAccess (Liste.First, Stapel.Pop) über ein gesuchtes Mitglied ein Element?
  /// </summary>
  function MemberRead(AAccess: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol,
    AType: TResolvedSymbol): Boolean;
  begin
    ACollection := nil;
    Result := (AAccess.Kind = TSyntaxKind.MemberAccess) and (AAccess.ChildCount = 1) and
      IsMember(AAccess.Name, AMembers) and IsLegacyCollection(AAccess[0], ASymbol, AType);
    if Result then
    begin
      ACollection := AAccess[0];
    end;
  end;

  /// <summary>Liest AValue ein Element einer gesuchten Sammlung? Dann deren Ausdruck, Deklaration und Typ.
  /// </summary>
  function ElementRead(AValue: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  begin
    Result := False;
    ACollection := nil;
    AValue := Unparenthesized(AValue);
    if AValue = nil then
    begin
      Exit;
    end;
    case AValue.Kind of
      TSyntaxKind.IndexAccess:
        Result := IndexedRead(AValue, ACollection, ASymbol, AType);
      TSyntaxKind.MemberAccess:
        // Liste.First, Stapel.Pop
        Result := MemberRead(AValue, ACollection, ASymbol, AType);
      TSyntaxKind.Call:
        // Liste.First(), Liste.Extract(Element)
        Result := (AValue.ChildCount >= 1) and MemberRead(AValue[0], ACollection, ASymbol, AType);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  /// <summary>Bezeichnet ANode sicher einen Typ, der als Element taugt?</summary>
  function IsCastType(ANode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    mSymbol: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := False;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.Identifier) or SameText(ANode.Name, 'Pointer') then
    begin
      Exit;
    end;
    if not AResolver.NodeType(ATree, AFileName, ANode, mSymbol, AType, mTypeFound) or not mSymbol.IsType then
    begin
      Exit;
    end;
    AType := mSymbol;
    Result := not SameText(mSymbol.Name, 'Pointer');
  end;

  procedure Add(ACast, AValue, ATypeNode: TSyntaxNode);
  var
    mRead: TLegacyCollectionRead;
  begin
    if not ElementRead(AValue, mRead.Collection, mRead.Symbol, mRead.CollectionType) or
      not IsCastType(ATypeNode, mRead.CastType) then
    begin
      Exit;
    end;
    mRead.Cast := ACast;
    mFound.Add(mRead);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        // T(Wert): Aufruf mit einem Argument, dessen Name ein Typ ist.
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and (mNode[0].Kind = TSyntaxKind.Identifier) then
        begin
          Add(mNode, mNode[1], mNode[0]);
        end
        // Wert as T
        else if (mNode.Kind = TSyntaxKind.BinaryExpr) and SameText(mNode.Name, 'as') and (mNode.ChildCount = 2) then
        begin
          Add(mNode, mNode[0], Unparenthesized(mNode[1]));
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

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mFound := TList<TLegacyCollectionRead>.Create;
  try
    Visit(ATree.Root);
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Kommt einer der Namen in AFileName vor? Unknown, sobald eine Datei nicht lesbar ist.</summary>
function NamesIn(const AFiles: IRuleProjectFiles; const AFileName: string;
  const ANames: TArray<string>): TRuleNameAnswer;
var
  mName: string;
begin
  Result := TRuleNameAnswer.Absent;
  for mName in ANames do
    case AFiles.NameIn(AFileName, mName) of
      TRuleNameAnswer.Present:
        Exit(TRuleNameAnswer.Present);
      TRuleNameAnswer.Unknown:
        Result := TRuleNameAnswer.Unknown;
    end;
end;

/// <summary>Gehört AFileName zu einem Projekt der Gruppe?</summary>
function InProjects(const AProjects: TArray<TRuleProject>; const AFileName: string): Boolean;
var
  mProject: TRuleProject;
  mSource: string;
begin
  Result := False;
  for mProject in AProjects do
  begin
    for mSource in mProject.Sources do
    begin
      if SameText(mSource, AFileName) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Lassen sich die übrigen Units der Projektgruppe prüfen? Sonst lehnt AConversion mit Grund ab.
/// </summary>
function OtherUnitsCheckable(const AContext: TRuleContext; const ANames: TArray<string>;
  AConversion: TGenericListConversion): Boolean;
var
  mReason: string;
begin
  Result := False;
  if AContext.ProjectFiles = nil then
  begin
    AConversion.Reject(cTexts[TCollectionsText.VisibleNoProject].Fmt([ANames[0]]));
  end
  else if not AContext.ProjectFiles.Complete(mReason) then
  begin
    AConversion.Reject(cTexts[TCollectionsText.VisibleNotReady].Fmt([ANames[0], mReason]));
  end
  else
  begin
    Result := True;
  end;
end;

/// <summary>Gibt die Unit ASource in die Umwandlung, wenn sie einen der Namen enthält; False, wenn sie nicht
/// lesbar ist (dann lehnt AConversion ab).</summary>
function AddOtherUnit(const AContext: TRuleContext; const AFileName, ASource: string; const ANames: TArray<string>;
  AConversion: TGenericListConversion): Boolean;
var
  mText: string;
begin
  Result := True;
  case NamesIn(AContext.ProjectFiles, ASource, ANames) of
    TRuleNameAnswer.Absent:
      Exit;
    TRuleNameAnswer.Unknown:
      Result := False;
  else
    // Die geprüfte Unit mit dem Text des Editors, alle anderen über die Projektdateien.
    if SameText(ASource, AFileName) then
    begin
      mText := AContext.Text;
    end
    else
    begin
      Result := AContext.ProjectFiles.ReadText(ASource, mText);
    end;
  end;
  if Result then
  begin
    AConversion.AddFile(mText, ASource);
  end
  else
  begin
    AConversion.Reject(cTexts[TCollectionsText.NotReadable].Fmt([ExtractFileName(ASource)]));
  end;
end;

/// <summary>Die Units der Projektgruppe, die die Sammlung unter einem ihrer äußeren Namen erreichen, in die
/// Umwandlung geben; ist eine nicht lesbar oder das Projekt unbekannt, scheidet die Umwandlung aus.</summary>
procedure AddOtherUnits(const AContext: TRuleContext; const AFileName, ADeclarationFile: string;
  AConversion: TGenericListConversion);
var
  mNames: TArray<string>;
  mSeen: TList<string>;
  mProject: TRuleProject;
  mSource: string;
begin
  mNames := AConversion.ExternalNames;
  if (mNames = nil) or not OtherUnitsCheckable(AContext, mNames, AConversion) then
  begin
    Exit;
  end;
  mSeen := TList<string>.Create;
  try
    mSeen.Add(LowerCase(ADeclarationFile));
    for mProject in AContext.ProjectFiles.ProjectsOf(ADeclarationFile, True) do
    begin
      for mSource in mProject.Sources do
      begin
        if mSeen.Contains(LowerCase(mSource)) then
        begin
          Continue;
        end;
        mSeen.Add(LowerCase(mSource));
        if not AddOtherUnit(AContext, AFileName, mSource, mNames, AConversion) then
        begin
          Exit;
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Korrektur aus dem Plan; die Edits der geprüften Datei AFileName in Edits, alle übrigen in
/// OtherFiles.</summary>
function FixFromPlan(const APlan: TGenericListPlan; const AFileName, ADeclarationFile: string): TRuleFix;
var
  mOthers: TArray<TFileTextEdits>;
  mFileEdits: TFileTextEdits;
  mOther: TRuleFileEdits;
begin
  if SameText(ADeclarationFile, AFileName) then
  begin
    Result := TRuleFix.Create(APlan.Title, APlan.Edits, APlan.Safe);
    mOthers := APlan.FileEdits;
  end
  else
  begin
    Result := TRuleFix.Create(APlan.Title, nil, False);
    mFileEdits.FileName := ADeclarationFile;
    mFileEdits.Edits := APlan.Edits;
    mOthers := [mFileEdits];
    for mFileEdits in APlan.FileEdits do
    begin
      if SameText(mFileEdits.FileName, AFileName) then
      begin
        Result.Edits := mFileEdits.Edits;
      end
      else
      begin
        mOthers := mOthers + [mFileEdits];
      end;
    end;
  end;
  for mFileEdits in mOthers do
  begin
    mOther.FileName := mFileEdits.FileName;
    mOther.Edits := mFileEdits.Edits;
    Result.OtherFiles := Result.OtherFiles + [mOther];
  end;
end;

type
  /// <summary>Datei mit der Deklaration einer Sammlung: Baum, Text, Name; OwnsTree, wenn der Baum eigens
  /// gelesen wurde.</summary>
  TLegacyDeclarationSource = record
    Tree: TSyntaxTree;
    Text: string;
    FileName: string;
    OwnsTree: Boolean;
  end;

/// <summary>Text der Datei AFile mit der Deklaration von ARead aus einer anderen Unit der Projektgruppe; False
/// mit Grund in AReason, wenn sie sich nicht sicher ändern lässt.</summary>
function ForeignDeclarationText(const AContext: TRuleContext; const AFileName: string;
  const ARead: TLegacyCollectionRead; const AFile: string; out AText, AReason: string): Boolean;
var
  mReason: string;
begin
  Result := False;
  AText := '';
  if AContext.ProjectFiles = nil then
  begin
    AReason := cTexts[TCollectionsText.DeclaredNoProject].Fmt([ARead.Symbol.Name, ARead.Symbol.UnitName]);
  end
  else if not AContext.ProjectFiles.Complete(mReason) then
  begin
    AReason := cTexts[TCollectionsText.DeclaredNotLoaded].Fmt([ARead.Symbol.Name, ARead.Symbol.UnitName, mReason]);
  end
  else if not InProjects(AContext.ProjectFiles.ProjectsOf(AFileName, True), AFile) then
  begin
    AReason := cTexts[TCollectionsText.DeclaredNoGroup].Fmt([ARead.Symbol.Name, ARead.Symbol.UnitName]);
  end
  else if not AContext.ProjectFiles.ReadText(AFile, AText) then
  begin
    AReason := cTexts[TCollectionsText.NotReadable].Fmt([ExtractFileName(AFile)]);
  end
  else
  begin
    Result := True;
  end;
end;

/// <summary>Die Deklaration steht in dieser Unit oder in einer anderen Unit der Projektgruppe.</summary>
function DeclarationSource(const AContext: TRuleContext; const AFileName: string;
  const ARead: TLegacyCollectionRead; out ASource: TLegacyDeclarationSource; out AReason: string): Boolean;
begin
  ASource := Default(TLegacyDeclarationSource);
  AReason := '';
  Result := True;
  if TLegacyCollections.DeclaredIn(ARead.Symbol, AFileName) then
  begin
    ASource.Tree := AContext.Tree;
    ASource.Text := AContext.Text;
    ASource.FileName := AFileName;
    Exit;
  end;
  ASource.FileName := ARead.Symbol.FileName;
  Result := ForeignDeclarationText(AContext, AFileName, ARead, ASource.FileName, ASource.Text, AReason);
  if Result then
  begin
    ASource.Tree := TSyntaxTreeCache.Parse(ASource.Text);
    ASource.OwnsTree := True;
  end;
end;

/// <summary>Plant die Umwandlung der Deklaration von ARead in ASource; liefert den Grund, wenn sie nicht sicher
/// möglich ist, sonst ''.</summary>
function PlanConversion(const AContext: TRuleContext; const AFileName: string; const ARead: TLegacyCollectionRead;
  const ASource: TLegacyDeclarationSource; AConversion: TGenericListConversion; out APlan: TGenericListPlan): string;
var
  mName: string;
  mDeclaration: TSyntaxNode;
begin
  Result := '';
  APlan := Default(TGenericListPlan);
  mName := ARead.Symbol.Name;
  mDeclaration := TGenericListConversion.DeclarationAt(ASource.Tree, ARead.Symbol.SelectionRange.StartPos, mName);
  if mDeclaration = nil then
  begin
    Exit(cTexts[TCollectionsText.NotFieldOrVariable].Fmt([ARead.Symbol.Name]));
  end;
  if AConversion.Start(ASource.Tree, ASource.Text, ASource.FileName, mDeclaration, mName) then
  begin
    AddOtherUnits(AContext, AFileName, ASource.FileName, AConversion);
  end;
  if not AConversion.Finish(APlan) then
  begin
    Result := AConversion.Reason;
  end;
end;

class function TLegacyCollections.ConversionFix(const AContext: TRuleContext; const AFileName: string;
  const ARead: TLegacyCollectionRead; AResolver: TNameResolver; out AFix: TRuleFix; out AReason: string): Boolean;
var
  mKind: TLegacyListKind;
  mSource: TLegacyDeclarationSource;
  mConversion: TGenericListConversion;
  mPlan: TGenericListPlan;
begin
  Result := False;
  AFix := Default(TRuleFix);
  AReason := '';
  if not TLegacyListKind.Find(ARead.CollectionType.Name, mKind) then
  begin
    AReason := cTexts[TCollectionsText.NoGeneric].Fmt([ARead.CollectionType.Name]);
    Exit;
  end;
  if not DeclarationSource(AContext, AFileName, ARead, mSource, AReason) then
  begin
    Exit;
  end;
  try
    mConversion := TGenericListConversion.Create(mKind, AResolver);
    try
      AReason := PlanConversion(AContext, AFileName, ARead, mSource, mConversion, mPlan);
      Result := AReason = '';
    finally
      mConversion.Free;
    end;
  finally
    if mSource.OwnsTree then
    begin
      mSource.Tree.Free;
    end;
  end;
  if Result then
  begin
    AFix := FixFromPlan(mPlan, AFileName, mSource.FileName);
  end;
end;

{ TLegacyCollectionRule }

/// <summary>Name der geprüften Datei; ohne Dateinamen der relative Pfad bzw. Unitname.pas.</summary>
function CheckedFileName(const AContext: TRuleContext): string;
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

/// <summary>Namen der Zieltypen aller Casts auf die Sammlung mit dem Schlüssel AKey, ohne Doppelte.</summary>
function CastTypeNames(const AReads: TArray<TLegacyCollectionRead>; const AKey: string): TArray<string>;
var
  mNames: TList<string>;
  mRead: TLegacyCollectionRead;
begin
  mNames := TList<string>.Create;
  try
    for mRead in AReads do
    begin
      if (mRead.Key = AKey) and not mNames.Contains(mRead.CastType.Name) then
      begin
        mNames.Add(mRead.CastType.Name);
      end;
    end;
    Result := mNames.ToArray;
  finally
    mNames.Free;
  end;
end;

procedure TLegacyCollectionRule.ReportCollection(const AContext: TRuleContext; const AReport: IRuleReport;
  const AFileName: string; const AFirst: TLegacyCollectionRead; const ACastTypes: TArray<string>;
  AResolver: TNameResolver);
var
  mRange: TTextRange;
  mFix: TRuleFix;
  mReason: string;
begin
  if TLegacyCollections.DeclaredIn(AFirst.Symbol, AFileName) then
  begin
    mRange := AFirst.Symbol.SelectionRange;
  end
  else
  begin
    mRange := TTextRange.Create(AFirst.Cast.StartPos, AFirst.Cast.EndPos);
  end;
  if TLegacyCollections.ConversionFix(AContext, AFileName, AFirst, AResolver, mFix, mReason) then
  begin
    AReport.Add(mRange, FindingMessage(AFirst.CollectionType.Name, ACastTypes), TRuleConfidence.High, [mFix]);
  end
  else
  begin
    AReport.AddWithDetails(mRange, FindingMessage(AFirst.CollectionType.Name, ACastTypes),
      cTexts[TCollectionsText.NoQuickFix].Text + mReason + '.', TRuleConfidence.High, nil);
  end;
end;

procedure TLegacyCollectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mReads: TArray<TLegacyCollectionRead>;
  mRead: TLegacyCollectionRead;
  mKeys: TList<string>;
begin
  // Kein Vorfilter über den Text: Die Liste kann in einer anderen Unit deklariert sein (Objekt.Liste[I]).
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
  begin
    Exit;
  end;
  mFileName := CheckedFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mReads := TLegacyCollections.Reads(AContext.Tree, mFileName, mResolver, CollectionTypes, ReadMembers,
      IndexedReads);
  finally
    mResolver.UnpinTree;
  end;
  mKeys := TList<string>.Create;
  try
    // Je Sammlung ein Treffer mit allen Zieltypen ihrer Casts.
    for mRead in mReads do
    begin
      if not mKeys.Contains(mRead.Key) then
      begin
        mKeys.Add(mRead.Key);
        ReportCollection(AContext, AReport, mFileName, mRead, CastTypeNames(mReads, mRead.Key), mResolver);
      end;
    end;
  finally
    mKeys.Free;
  end;
end;

{ TLegacyTListRule }

function TLegacyTListRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLegacyTListRuleId, TRuleSeverity.Information,
    cTexts[TCollectionsText.ListTitle].Text,
    True);
end;

function TLegacyTListRule.CollectionTypes: TArray<TLegacyCollectionType>;
begin
  Result := [TLegacyCollectionType.Create('System.Classes', 'Classes', 'TList'),
    TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TObjectList')];
end;

function TLegacyTListRule.ReadMembers: TArray<string>;
begin
  Result := ['First', 'Last', 'Extract'];
end;

function TLegacyTListRule.IndexedReads: Boolean;
begin
  Result := True;
end;

function TLegacyTListRule.FindingMessage(const ACollectionType: string; const ACastTypes: TArray<string>): string;
begin
  if Length(ACastTypes) = 1 then
  begin
    Result := cTexts[TCollectionsText.ListCast].Fmt([ACollectionType, ACollectionType, ACastTypes[0]]);
  end
  else
  begin
    Result := cTexts[TCollectionsText.ListCasts].Fmt([ACollectionType, string.Join(', ', ACastTypes)]);
  end;
end;

{ TLegacyStackQueueRule }

function TLegacyStackQueueRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLegacyStackQueueRuleId, TRuleSeverity.Information,
    cTexts[TCollectionsText.StackTitle].Text, True);
end;

function TLegacyStackQueueRule.CollectionTypes: TArray<TLegacyCollectionType>;
begin
  Result := [TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TStack'),
    TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TQueue'),
    TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TObjectStack'),
    TLegacyCollectionType.Create('System.Contnrs', 'Contnrs', 'TObjectQueue')];
end;

function TLegacyStackQueueRule.ReadMembers: TArray<string>;
begin
  Result := ['Pop', 'Peek', 'Extract'];
end;

function TLegacyStackQueueRule.IndexedReads: Boolean;
begin
  // TOrderedList hat keinen Index.
  Result := False;
end;

function TLegacyStackQueueRule.FindingMessage(const ACollectionType: string;
  const ACastTypes: TArray<string>): string;
var
  mStack: Boolean;
  mAdjective, mGeneric: string;
begin
  // Der Stapel, die Warteschlange.
  mStack := EndsText('Stack', ACollectionType);
  if mStack then
  begin
    mAdjective := cTexts[TCollectionsText.NonGeneric].Text;
    mGeneric := cTexts[TCollectionsText.GenericStack].Text;
  end
  else
  begin
    mAdjective := cTexts[TCollectionsText.NonGenericFem].Text;
    mGeneric := cTexts[TCollectionsText.GenericQueue].Text;
  end;
  if Length(ACastTypes) = 1 then
  begin
    Result := cTexts[TCollectionsText.StackCast].Fmt([mAdjective, ACollectionType, ACollectionType, ACastTypes[0]]);
  end
  else
  begin
    Result := cTexts[TCollectionsText.StackCasts].Fmt(
      [mAdjective, ACollectionType, string.Join(', ', ACastTypes), mGeneric]);
  end;
end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLegacyTListRule.Create);
  ARegistry.Register(TLegacyStackQueueRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Collections', cTexts);

end.
