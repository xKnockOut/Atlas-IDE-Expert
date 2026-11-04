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
  LegacyTListRuleId = 'legacy-tlist';
  LegacyStackQueueRuleId = 'legacy-stack-queue';

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
  Atlas.Common.Editing.GenericLists;

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
  Member: string;
begin
  Result := False;
  for Member in AMembers do
  begin
    if SameText(Member, AName) then
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
  Found: TList<TLegacyCollectionRead>;

  /// <summary>Ist ANode sicher eine Sammlung der gesuchten Typen? Dann Deklaration und Typ.</summary>
  function IsLegacyCollection(ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    TypeFound: Boolean;
    Wanted: TLegacyCollectionType;
  begin
    Result := False;
    if (ANode = nil) or not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess,
      TSyntaxKind.IndexAccess, TSyntaxKind.Call]) then
    begin
      Exit;
    end;
    if not AResolver.NodeType(ATree, AFileName, ANode, ASymbol, AType, TypeFound) or not TypeFound or
      ASymbol.IsType or not AType.IsType then
    begin
      Exit;
    end;
    if (AType.TypeParams <> '') or (Pos('<', ASymbol.TypeName) > 0) then
    begin
      Exit;
    end;
    for Wanted in ATypes do
    begin
      Result := Result or SameText(AType.Name, Wanted.TypeName) and (SameText(AType.UnitName, Wanted.UnitName) or
        SameText(AType.UnitName, Wanted.ShortUnitName));
    end;
  end;

  /// <summary>Liste[I], Liste.Items[I], Objekt.Liste[I].</summary>
  function IndexedRead(AValue: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol,
    AType: TResolvedSymbol): Boolean;
  var
    Base: TSyntaxNode;
  begin
    Result := False;
    ACollection := nil;
    if not AIndexed or (AValue.ChildCount <> 2) then
    begin
      Exit;
    end;
    Base := AValue[0];
    if (Base.Kind = TSyntaxKind.MemberAccess) and SameText(Base.Name, 'Items') and (Base.ChildCount = 1) and
      IsLegacyCollection(Base[0], ASymbol, AType) then
    begin
      ACollection := Base[0];
    end
    else if IsLegacyCollection(Base, ASymbol, AType) then
    begin
      ACollection := Base;
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
    Symbol: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := False;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.Identifier) or SameText(ANode.Name, 'Pointer') then
    begin
      Exit;
    end;
    if not AResolver.NodeType(ATree, AFileName, ANode, Symbol, AType, TypeFound) or not Symbol.IsType then
    begin
      Exit;
    end;
    AType := Symbol;
    Result := not SameText(Symbol.Name, 'Pointer');
  end;

  procedure Add(ACast, AValue, ATypeNode: TSyntaxNode);
  var
    Read: TLegacyCollectionRead;
  begin
    if not ElementRead(AValue, Read.Collection, Read.Symbol, Read.CollectionType) or
      not IsCastType(ATypeNode, Read.CastType) then
    begin
      Exit;
    end;
    Read.Cast := ACast;
    Found.Add(Read);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        // T(Wert): Aufruf mit einem Argument, dessen Name ein Typ ist.
        if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount = 2) and (Node[0].Kind = TSyntaxKind.Identifier) then
        begin
          Add(Node, Node[1], Node[0]);
        end
        // Wert as T
        else if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, 'as') and (Node.ChildCount = 2) then
        begin
          Add(Node, Node[0], Unparenthesized(Node[1]));
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

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Found := TList<TLegacyCollectionRead>.Create;
  try
    Visit(ATree.Root);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

/// <summary>Kommt einer der Namen in AFileName vor? Unknown, sobald eine Datei nicht lesbar ist.</summary>
function NamesIn(const AFiles: IRuleProjectFiles; const AFileName: string;
  const ANames: TArray<string>): TRuleNameAnswer;
var
  Name: string;
begin
  Result := TRuleNameAnswer.Absent;
  for Name in ANames do
    case AFiles.NameIn(AFileName, Name) of
      TRuleNameAnswer.Present:
        Exit(TRuleNameAnswer.Present);
      TRuleNameAnswer.Unknown:
        Result := TRuleNameAnswer.Unknown;
    end;
end;

/// <summary>Gehört AFileName zu einem Projekt der Gruppe?</summary>
function InProjects(const AProjects: TArray<TRuleProject>; const AFileName: string): Boolean;
var
  Project: TRuleProject;
  Source: string;
begin
  Result := False;
  for Project in AProjects do
  begin
    for Source in Project.Sources do
    begin
      if SameText(Source, AFileName) then
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
  Reason: string;
begin
  Result := False;
  if AContext.ProjectFiles = nil then
  begin
    AConversion.Reject(Format('%s ist auch in anderen Units sichtbar, und ohne geladenes Projekt lassen sie sich ' +
      'nicht prüfen', [ANames[0]]));
  end
  else if not AContext.ProjectFiles.Complete(Reason) then
  begin
    AConversion.Reject(Format('%s ist auch in anderen Units sichtbar, die sich noch nicht prüfen lassen (%s)',
      [ANames[0], Reason]));
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
  Text: string;
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
      Text := AContext.Text;
    end
    else
    begin
      Result := AContext.ProjectFiles.ReadText(ASource, Text);
    end;
  end;
  if Result then
  begin
    AConversion.AddFile(Text, ASource);
  end
  else
  begin
    AConversion.Reject(Format('%s ist nicht lesbar', [ExtractFileName(ASource)]));
  end;
end;

/// <summary>Die Units der Projektgruppe, die die Sammlung unter einem ihrer äußeren Namen erreichen, in die
/// Umwandlung geben; ist eine nicht lesbar oder das Projekt unbekannt, scheidet die Umwandlung aus.</summary>
procedure AddOtherUnits(const AContext: TRuleContext; const AFileName, ADeclarationFile: string;
  AConversion: TGenericListConversion);
var
  Names: TArray<string>;
  Seen: TList<string>;
  Project: TRuleProject;
  Source: string;
begin
  Names := AConversion.ExternalNames;
  if (Names = nil) or not OtherUnitsCheckable(AContext, Names, AConversion) then
  begin
    Exit;
  end;
  Seen := TList<string>.Create;
  try
    Seen.Add(LowerCase(ADeclarationFile));
    for Project in AContext.ProjectFiles.ProjectsOf(ADeclarationFile, True) do
    begin
      for Source in Project.Sources do
      begin
        if Seen.Contains(LowerCase(Source)) then
        begin
          Continue;
        end;
        Seen.Add(LowerCase(Source));
        if not AddOtherUnit(AContext, AFileName, Source, Names, AConversion) then
        begin
          Exit;
        end;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

/// <summary>Korrektur aus dem Plan; die Edits der geprüften Datei AFileName in Edits, alle übrigen in
/// OtherFiles.</summary>
function FixFromPlan(const APlan: TGenericListPlan; const AFileName, ADeclarationFile: string): TRuleFix;
var
  Others: TArray<TFileTextEdits>;
  FileEdits: TFileTextEdits;
  Other: TRuleFileEdits;
begin
  if SameText(ADeclarationFile, AFileName) then
  begin
    Result := TRuleFix.Create(APlan.Title, APlan.Edits, APlan.Safe);
    Others := APlan.FileEdits;
  end
  else
  begin
    Result := TRuleFix.Create(APlan.Title, nil, False);
    FileEdits.FileName := ADeclarationFile;
    FileEdits.Edits := APlan.Edits;
    Others := [FileEdits];
    for FileEdits in APlan.FileEdits do
    begin
      if SameText(FileEdits.FileName, AFileName) then
      begin
        Result.Edits := FileEdits.Edits;
      end
      else
      begin
        Others := Others + [FileEdits];
      end;
    end;
  end;
  for FileEdits in Others do
  begin
    Other.FileName := FileEdits.FileName;
    Other.Edits := FileEdits.Edits;
    Result.OtherFiles := Result.OtherFiles + [Other];
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
  Reason: string;
begin
  Result := False;
  AText := '';
  if AContext.ProjectFiles = nil then
  begin
    AReason := Format('%s ist in %s deklariert, und ohne geladenes Projekt lässt sich die Unit nicht ändern',
      [ARead.Symbol.Name, ARead.Symbol.UnitName]);
  end
  else if not AContext.ProjectFiles.Complete(Reason) then
  begin
    AReason := Format('%s ist in %s deklariert, und das Projekt ist noch nicht vollständig geladen (%s)',
      [ARead.Symbol.Name, ARead.Symbol.UnitName, Reason]);
  end
  else if not InProjects(AContext.ProjectFiles.ProjectsOf(AFileName, True), AFile) then
  begin
    AReason := Format('%s ist in %s deklariert, die zu keinem Projekt der Gruppe gehört',
      [ARead.Symbol.Name, ARead.Symbol.UnitName]);
  end
  else if not AContext.ProjectFiles.ReadText(AFile, AText) then
  begin
    AReason := Format('%s ist nicht lesbar', [ExtractFileName(AFile)]);
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
  Name: string;
  Declaration: TSyntaxNode;
begin
  Result := '';
  APlan := Default(TGenericListPlan);
  Name := ARead.Symbol.Name;
  Declaration := TGenericListConversion.DeclarationAt(ASource.Tree, ARead.Symbol.SelectionRange.StartPos, Name);
  if Declaration = nil then
  begin
    Exit(Format('Die Deklaration von %s ist kein Feld und keine Variable', [ARead.Symbol.Name]));
  end;
  if AConversion.Start(ASource.Tree, ASource.Text, ASource.FileName, Declaration, Name) then
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
  Kind: TLegacyListKind;
  Source: TLegacyDeclarationSource;
  Conversion: TGenericListConversion;
  Plan: TGenericListPlan;
begin
  Result := False;
  AFix := Default(TRuleFix);
  AReason := '';
  if not TLegacyListKind.Find(ARead.CollectionType.Name, Kind) then
  begin
    AReason := Format('Für %s gibt es kein generisches Gegenstück', [ARead.CollectionType.Name]);
    Exit;
  end;
  if not DeclarationSource(AContext, AFileName, ARead, Source, AReason) then
  begin
    Exit;
  end;
  try
    Conversion := TGenericListConversion.Create(Kind, AResolver);
    try
      AReason := PlanConversion(AContext, AFileName, ARead, Source, Conversion, Plan);
      Result := AReason = '';
    finally
      Conversion.Free;
    end;
  finally
    if Source.OwnsTree then
    begin
      Source.Tree.Free;
    end;
  end;
  if Result then
  begin
    AFix := FixFromPlan(Plan, AFileName, Source.FileName);
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
  Names: TList<string>;
  Read: TLegacyCollectionRead;
begin
  Names := TList<string>.Create;
  try
    for Read in AReads do
    begin
      if (Read.Key = AKey) and not Names.Contains(Read.CastType.Name) then
      begin
        Names.Add(Read.CastType.Name);
      end;
    end;
    Result := Names.ToArray;
  finally
    Names.Free;
  end;
end;

procedure TLegacyCollectionRule.ReportCollection(const AContext: TRuleContext; const AReport: IRuleReport;
  const AFileName: string; const AFirst: TLegacyCollectionRead; const ACastTypes: TArray<string>;
  AResolver: TNameResolver);
var
  Range: TTextRange;
  Fix: TRuleFix;
  Reason: string;
begin
  if TLegacyCollections.DeclaredIn(AFirst.Symbol, AFileName) then
  begin
    Range := AFirst.Symbol.SelectionRange;
  end
  else
  begin
    Range := TTextRange.Create(AFirst.Cast.StartPos, AFirst.Cast.EndPos);
  end;
  if TLegacyCollections.ConversionFix(AContext, AFileName, AFirst, AResolver, Fix, Reason) then
  begin
    AReport.Add(Range, FindingMessage(AFirst.CollectionType.Name, ACastTypes), TRuleConfidence.High, [Fix]);
  end
  else
  begin
    AReport.AddWithDetails(Range, FindingMessage(AFirst.CollectionType.Name, ACastTypes),
      'Keine Schnellkorrektur: ' + Reason + '.', TRuleConfidence.High, nil);
  end;
end;

procedure TLegacyCollectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Reads: TArray<TLegacyCollectionRead>;
  Read: TLegacyCollectionRead;
  Keys: TList<string>;
begin
  // Kein Vorfilter über den Text: Die Liste kann in einer anderen Unit deklariert sein (Objekt.Liste[I]).
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
  begin
    Exit;
  end;
  FileName := CheckedFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Reads := TLegacyCollections.Reads(AContext.Tree, FileName, Resolver, CollectionTypes, ReadMembers,
      IndexedReads);
  finally
    Resolver.UnpinTree;
  end;
  Keys := TList<string>.Create;
  try
    // Je Sammlung ein Treffer mit allen Zieltypen ihrer Casts.
    for Read in Reads do
    begin
      if not Keys.Contains(Read.Key) then
      begin
        Keys.Add(Read.Key);
        ReportCollection(AContext, AReport, FileName, Read, CastTypeNames(Reads, Read.Key), Resolver);
      end;
    end;
  finally
    Keys.Free;
  end;
end;

{ TLegacyTListRule }

function TLegacyTListRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LegacyTListRuleId, TRuleSeverity.Information, 'Ungenerische Liste mit Cast',
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
    Result := Format('Ungenerische %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.',
      [ACollectionType, ACollectionType, ACastTypes[0]]);
  end
  else
  begin
    Result := Format('Ungenerische %s mit Casts auf %s beim Lesen; eine generische Liste prüft den Typ ' +
      'beim Übersetzen.', [ACollectionType, string.Join(', ', ACastTypes)]);
  end;
end;

{ TLegacyStackQueueRule }

function TLegacyStackQueueRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LegacyStackQueueRuleId, TRuleSeverity.Information,
    'Ungenerischer Stapel oder ungenerische Warteschlange mit Cast', True);
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
  Stack: Boolean;
  Adjective, Generic: string;
begin
  // Der Stapel, die Warteschlange.
  Stack := EndsText('Stack', ACollectionType);
  if Stack then
  begin
    Adjective := 'Ungenerischer';
    Generic := 'ein generischer Stapel';
  end
  else
  begin
    Adjective := 'Ungenerische';
    Generic := 'eine generische Warteschlange';
  end;
  if Length(ACastTypes) = 1 then
  begin
    Result := Format('%s %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.',
      [Adjective, ACollectionType, ACollectionType, ACastTypes[0]]);
  end
  else
  begin
    Result := Format('%s %s mit Casts auf %s beim Lesen; %s prüft den Typ beim Übersetzen.',
      [Adjective, ACollectionType, string.Join(', ', ACastTypes), Generic]);
  end;
end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLegacyTListRule.Create);
  ARegistry.Register(TLegacyStackQueueRule.Create);
end;

end.
