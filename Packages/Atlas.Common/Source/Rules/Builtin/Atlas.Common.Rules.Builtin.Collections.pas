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
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CodeActions,
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
    Result := Result[0];
end;

function IsMember(const AName: string; const AMembers: TArray<string>): Boolean;
var
  Member: string;
begin
  Result := False;
  for Member in AMembers do
    if SameText(Member, AName) then
      Exit(True);
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
      Exit;
    if not AResolver.NodeType(ATree, AFileName, ANode, ASymbol, AType, TypeFound) or not TypeFound or
      ASymbol.IsType or not AType.IsType or (AType.TypeParams <> '') or (Pos('<', ASymbol.TypeName) > 0) then
      Exit;
    for Wanted in ATypes do
      if SameText(AType.Name, Wanted.TypeName) and (SameText(AType.UnitName, Wanted.UnitName) or
        SameText(AType.UnitName, Wanted.ShortUnitName)) then
        Exit(True);
  end;

  /// <summary>Liest AValue ein Element einer gesuchten Sammlung? Dann deren Ausdruck, Deklaration und Typ.
  /// </summary>
  function ElementRead(AValue: TSyntaxNode; out ACollection: TSyntaxNode; out ASymbol, AType: TResolvedSymbol): Boolean;
  var
    Base: TSyntaxNode;
  begin
    Result := False;
    ACollection := nil;
    AValue := Unparenthesized(AValue);
    if AValue = nil then
      Exit;
    case AValue.Kind of
      TSyntaxKind.IndexAccess:
        begin
          // Liste[I], Liste.Items[I], Objekt.Liste[I]
          if not AIndexed or (AValue.ChildCount <> 2) then
            Exit;
          Base := AValue[0];
          if (Base.Kind = TSyntaxKind.MemberAccess) and SameText(Base.Name, 'Items') and (Base.ChildCount = 1) and
            IsLegacyCollection(Base[0], ASymbol, AType) then
          begin
            ACollection := Base[0];
            Exit(True);
          end;
          if IsLegacyCollection(Base, ASymbol, AType) then
          begin
            ACollection := Base;
            Exit(True);
          end;
        end;
      TSyntaxKind.MemberAccess:
        // Liste.First, Stapel.Pop
        if (AValue.ChildCount = 1) and IsMember(AValue.Name, AMembers) and
          IsLegacyCollection(AValue[0], ASymbol, AType) then
        begin
          ACollection := AValue[0];
          Exit(True);
        end;
      TSyntaxKind.Call:
        // Liste.First(), Liste.Extract(Element)
        if (AValue.ChildCount >= 1) and (AValue[0].Kind = TSyntaxKind.MemberAccess) and
          (AValue[0].ChildCount = 1) and IsMember(AValue[0].Name, AMembers) and
          IsLegacyCollection(AValue[0][0], ASymbol, AType) then
        begin
          ACollection := AValue[0][0];
          Exit(True);
        end;
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
      Exit;
    if not AResolver.NodeType(ATree, AFileName, ANode, Symbol, AType, TypeFound) or not Symbol.IsType then
      Exit;
    AType := Symbol;
    Result := not SameText(Symbol.Name, 'Pointer');
  end;

  procedure Add(ACast, AValue, ATypeNode: TSyntaxNode);
  var
    Read: TLegacyCollectionRead;
  begin
    if not ElementRead(AValue, Read.Collection, Read.Symbol, Read.CollectionType) or
      not IsCastType(ATypeNode, Read.CastType) then
      Exit;
    Read.Cast := ACast;
    Found.Add(Read);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    // T(Wert): Aufruf mit einem Argument, dessen Name ein Typ ist.
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) then
      Add(ANode, ANode[1], ANode[0])
    // Wert as T
    else if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'as') and (ANode.ChildCount = 2) then
      Add(ANode, ANode[0], Unparenthesized(ANode[1]));
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
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
    for Source in Project.Sources do
      if SameText(Source, AFileName) then
        Exit(True);
end;

/// <summary>Die Units der Projektgruppe, die die Sammlung unter einem ihrer äußeren Namen erreichen, in die
/// Umwandlung geben; ist eine nicht lesbar oder das Projekt unbekannt, scheidet die Umwandlung aus.</summary>
procedure AddOtherUnits(const AContext: TRuleContext; const AFileName, ADeclarationFile: string;
  AConversion: TGenericListConversion);
var
  Names: TArray<string>;
  Seen: TList<string>;
  Project: TRuleProject;
  Source, Text, Reason: string;
begin
  Names := AConversion.ExternalNames;
  if Names = nil then
    Exit;
  if AContext.ProjectFiles = nil then
  begin
    AConversion.Reject(Format('%s ist auch in anderen Units sichtbar, und ohne geladenes Projekt lassen sie sich ' +
      'nicht prüfen', [Names[0]]));
    Exit;
  end;
  if not AContext.ProjectFiles.Complete(Reason) then
  begin
    AConversion.Reject(Format('%s ist auch in anderen Units sichtbar, die sich noch nicht prüfen lassen (%s)',
      [Names[0], Reason]));
    Exit;
  end;
  Seen := TList<string>.Create;
  try
    Seen.Add(LowerCase(ADeclarationFile));
    for Project in AContext.ProjectFiles.ProjectsOf(ADeclarationFile, True) do
      for Source in Project.Sources do
      begin
        if Seen.Contains(LowerCase(Source)) then
          Continue;
        Seen.Add(LowerCase(Source));
        case NamesIn(AContext.ProjectFiles, Source, Names) of
          TRuleNameAnswer.Absent:
            Continue;
          TRuleNameAnswer.Unknown:
            begin
              AConversion.Reject(Format('%s ist nicht lesbar', [ExtractFileName(Source)]));
              Exit;
            end;
        end;
        // Die geprüfte Unit mit dem Text des Editors, alle anderen über die Projektdateien.
        if SameText(Source, AFileName) then
          Text := AContext.Text
        else if not AContext.ProjectFiles.ReadText(Source, Text) then
        begin
          AConversion.Reject(Format('%s ist nicht lesbar', [ExtractFileName(Source)]));
          Exit;
        end;
        AConversion.AddFile(Text, Source);
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
      if SameText(FileEdits.FileName, AFileName) then
        Result.Edits := FileEdits.Edits
      else
        Others := Others + [FileEdits];
  end;
  for FileEdits in Others do
  begin
    Other.FileName := FileEdits.FileName;
    Other.Edits := FileEdits.Edits;
    Result.OtherFiles := Result.OtherFiles + [Other];
  end;
end;

class function TLegacyCollections.ConversionFix(const AContext: TRuleContext; const AFileName: string;
  const ARead: TLegacyCollectionRead; AResolver: TNameResolver; out AFix: TRuleFix; out AReason: string): Boolean;
var
  Kind: TLegacyListKind;
  Tree: TSyntaxTree;
  OwnsTree: Boolean;
  Text, DeclarationFile, Name, Reason: string;
  Declaration: TSyntaxNode;
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
  // Die Deklaration steht in dieser Unit oder in einer anderen Unit der Projektgruppe.
  OwnsTree := False;
  if DeclaredIn(ARead.Symbol, AFileName) then
  begin
    Tree := AContext.Tree;
    Text := AContext.Text;
    DeclarationFile := AFileName;
  end
  else
  begin
    DeclarationFile := ARead.Symbol.FileName;
    if AContext.ProjectFiles = nil then
    begin
      AReason := Format('%s ist in %s deklariert, und ohne geladenes Projekt lässt sich die Unit nicht ändern',
        [ARead.Symbol.Name, ARead.Symbol.UnitName]);
      Exit;
    end;
    if not AContext.ProjectFiles.Complete(Reason) then
    begin
      AReason := Format('%s ist in %s deklariert, und das Projekt ist noch nicht vollständig geladen (%s)',
        [ARead.Symbol.Name, ARead.Symbol.UnitName, Reason]);
      Exit;
    end;
    if not InProjects(AContext.ProjectFiles.ProjectsOf(AFileName, True), DeclarationFile) then
    begin
      AReason := Format('%s ist in %s deklariert, die zu keinem Projekt der Gruppe gehört',
        [ARead.Symbol.Name, ARead.Symbol.UnitName]);
      Exit;
    end;
    if not AContext.ProjectFiles.ReadText(DeclarationFile, Text) then
    begin
      AReason := Format('%s ist nicht lesbar', [ExtractFileName(DeclarationFile)]);
      Exit;
    end;
    Tree := TSyntaxTreeCache.Parse(Text);
    OwnsTree := True;
  end;
  try
    Name := ARead.Symbol.Name;
    Declaration := TGenericListConversion.DeclarationAt(Tree, ARead.Symbol.SelectionRange.StartPos, Name);
    if Declaration = nil then
    begin
      AReason := Format('Die Deklaration von %s ist kein Feld und keine Variable', [ARead.Symbol.Name]);
      Exit;
    end;
    Conversion := TGenericListConversion.Create(Kind, AResolver);
    try
      if Conversion.Start(Tree, Text, DeclarationFile, Declaration, Name) then
        AddOtherUnits(AContext, AFileName, DeclarationFile, Conversion);
      if not Conversion.Finish(Plan) then
      begin
        AReason := Conversion.Reason;
        Exit;
      end;
    finally
      Conversion.Free;
    end;
  finally
    if OwnsTree then
      Tree.Free;
  end;
  AFix := FixFromPlan(Plan, AFileName, DeclarationFile);
  Result := True;
end;

{ TLegacyCollectionRule }

procedure TLegacyCollectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  FileName, Key, Reason: string;
  Reads: TArray<TLegacyCollectionRead>;
  Read, First: TLegacyCollectionRead;
  Keys: TList<string>;
  CastTypes: TList<string>;
  Range: TTextRange;
  Index: Integer;
  Fix: TRuleFix;
begin
  // Kein Vorfilter über den Text: Die Liste kann in einer anderen Unit deklariert sein (Objekt.Liste[I]).
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or (AContext.Index = nil) then
    Exit;
  FileName := AContext.FileName;
  if FileName = '' then
    FileName := AContext.RelativePath;
  if FileName = '' then
    FileName := AContext.UnitName + '.pas';
  Keys := nil;
  CastTypes := nil;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Reads := TLegacyCollections.Reads(AContext.Tree, FileName, Resolver, CollectionTypes, ReadMembers,
        IndexedReads);
    finally
      Resolver.UnpinTree;
    end;
    Keys := TList<string>.Create;
    CastTypes := TList<string>.Create;
    // Je Sammlung ein Treffer mit allen Zieltypen ihrer Casts.
    for Read in Reads do
    begin
      Key := Read.Key;
      if Keys.Contains(Key) then
        Continue;
      Keys.Add(Key);
      First := Read;
      CastTypes.Clear;
      for Index := 0 to High(Reads) do
        if (Reads[Index].Key = Key) and not CastTypes.Contains(Reads[Index].CastType.Name) then
          CastTypes.Add(Reads[Index].CastType.Name);
      if TLegacyCollections.DeclaredIn(First.Symbol, FileName) then
        Range := First.Symbol.SelectionRange
      else
        Range := TTextRange.Create(First.Cast.StartPos, First.Cast.EndPos);
      if TLegacyCollections.ConversionFix(AContext, FileName, First, Resolver, Fix, Reason) then
        AReport.Add(Range, FindingMessage(First.CollectionType.Name, CastTypes.ToArray), TRuleConfidence.High,
          [Fix])
      else
        AReport.AddWithDetails(Range, FindingMessage(First.CollectionType.Name, CastTypes.ToArray),
          'Keine Schnellkorrektur: ' + Reason + '.', TRuleConfidence.High, nil);
    end;
  finally
    CastTypes.Free;
    Keys.Free;
    Resolver.Free;
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
    Result := Format('Ungenerische %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.',
      [ACollectionType, ACollectionType, ACastTypes[0]])
  else
    Result := Format('Ungenerische %s mit Casts auf %s beim Lesen; eine generische Liste prüft den Typ ' +
      'beim Übersetzen.', [ACollectionType, string.Join(', ', ACastTypes)]);
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
    Result := Format('%s %s mit Cast beim Lesen; %s<%s> prüft den Typ beim Übersetzen.',
      [Adjective, ACollectionType, ACollectionType, ACastTypes[0]])
  else
    Result := Format('%s %s mit Casts auf %s beim Lesen; %s prüft den Typ beim Übersetzen.',
      [Adjective, ACollectionType, string.Join(', ', ACastTypes), Generic]);
end;

procedure RegisterCollectionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLegacyTListRule.Create);
  ARegistry.Register(TLegacyStackQueueRule.Create);
end;

end.
