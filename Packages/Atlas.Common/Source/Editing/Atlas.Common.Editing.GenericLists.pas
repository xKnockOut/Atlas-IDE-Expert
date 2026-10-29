unit Atlas.Common.Editing.GenericLists;

// Ungenerische Listen in generische umwandeln (#1105 legacy-tlist, #1106 Stapel
// und Warteschlangen): TList → TList<T>, TObjectList (Contnrs) →
// TObjectList<T>, TStack/TQueue/TObjectStack/TObjectQueue → die Gegenstücke
// aus System.Generics.Collections. Was eine Listenart kann, beschreibt
// TLegacyListKind; die Regeln geben nur die Art und die Deklaration herein.
//
// - Elementtyp T: Alle Lesezugriffe (L[I], L.Items[I], First, Last, Pop, Peek,
//   Extract, for … in) müssen denselben Cast haben, T(L[I]) oder L[I] as T.
//   Lesen ohne Cast ist nur erlaubt, wo der genauere Typ nichts ändert:
//   Vergleich mit nil, Assigned, Zuweisung an einen Pointer und bei
//   Objektlisten Free und andere TObject-Mitglieder.
// - Umgeschrieben werden die Deklaration (bei "A, B: TList" wird L
//   abgespalten), jedes Create (Argumente bleiben; bei TObjectStack/-Queue,
//   deren generische Klassen ihre Objekte besitzen, Create(False)), die Casts,
//   umbenannte Methoden (Push → Enqueue …), Schleifenvariablen von for … in
//   (Typ Pointer → T) und eine Property, die das Feld direkt liest
//   (property Items: TList read FItems). System.Generics.Collections kommt in
//   das uses des Abschnitts, in dem der generische Typ steht; Contnrs entfällt,
//   wenn die Unit danach keinen Typ daraus mehr nennt.
// - Keine Umwandlung (Grund in Reason): Methoden ohne Gegenstück (Sort mit
//   TListSortCompare, Assign mit TListAssignOp, List, Expand, Pack …),
//   Elemente als Pointer oder Ganzzahl (Add(Pointer(…)), Integer(L[I])),
//   Argumente von Add/Insert/Extract/Remove/IndexOf mit anderem Typ als T,
//   Weitergabe der Liste (an Parameter, Result, andere Variablen, with),
//   Erzeugen mit einer anderen Klasse, Properties mit Getter, Parameter und
//   Funktionsergebnisse vom alten Typ. Ist die Liste außerhalb der Unit
//   sichtbar (Feld oder Property nicht privat, globale Variable im
//   interface), nennt ExternalNames die Namen; der Aufrufer gibt die Units,
//   die einen davon enthalten, über AddFile herein. Deren Stellen werden nach
//   denselben Regeln umgeschrieben oder verhindern die Umwandlung.
// - Safe: Alle Argumente haben einen bekannten, passenden Typ, und nur die
//   eigene Datei ändert sich. Sonst bietet die Regel die Korrektur nur als
//   Code-Aktion an, nicht in source.fixAll.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions;

type
  /// <summary>Eine ungenerische Listenklasse und ihr generisches Gegenstück (#1105, #1106).</summary>
  TLegacyListKind = record
    /// <summary>Name der alten Klasse, z. B. TList oder TObjectStack.</summary>
    LegacyName: string;
    /// <summary>Name der generischen Klasse ohne Typargument.</summary>
    GenericName: string;
    /// <summary>Unit der alten Klasse ohne Namespace (Classes, Contnrs); Contnrs entfällt, wenn ungenutzt.</summary>
    LegacyUnit: string;
    /// <summary>Mitglieder ohne Elementtyp, z. B. Count, Clear, Delete.</summary>
    Neutral: TArray<string>;
    /// <summary>Mitglieder, die ein Element liefern, z. B. Items, First, Pop.</summary>
    Reads: TArray<string>;
    /// <summary>Mitglieder mit einem Element als Argument: Name=Position ab 0, z. B. Add=0, Insert=1.</summary>
    ElementArgs: TArray<string>;
    /// <summary>Umbenennungen Alt=Neu, z. B. Push=Enqueue.</summary>
    Renames: TArray<string>;
    /// <summary>Mitglieder ohne sicheres Gegenstück: Name=Grund.</summary>
    Unsupported: TArray<string>;
    /// <summary>Argumente für ein Create ohne Argumente, z. B. False; '' = keine.</summary>
    CreateArguments: string;
    /// <summary>Die Elemente müssen Klassen sein (TObjectList&lt;T: class&gt;).</summary>
    ClassOnly: Boolean;
    /// <summary>L[I] steht für L.Items[I].</summary>
    DefaultItems: Boolean;
    /// <summary>TList aus System.Classes.</summary>
    class function PointerList: TLegacyListKind; static;
    /// <summary>TObjectList aus System.Contnrs.</summary>
    class function ObjectList: TLegacyListKind; static;
    /// <summary>TStack aus System.Contnrs.</summary>
    class function Stack: TLegacyListKind; static;
    /// <summary>TQueue aus System.Contnrs.</summary>
    class function Queue: TLegacyListKind; static;
    /// <summary>TObjectStack aus System.Contnrs.</summary>
    class function ObjectStack: TLegacyListKind; static;
    /// <summary>TObjectQueue aus System.Contnrs.</summary>
    class function ObjectQueue: TLegacyListKind; static;
    /// <summary>Art zu einem alten Klassennamen (ohne Unit-Präfix); False, wenn unbekannt.</summary>
    class function Find(const ALegacyName: string; out AKind: TLegacyListKind): Boolean; static;
  end;

  /// <summary>Ergebnis der Umwandlung.</summary>
  TGenericListPlan = record
    /// <summary>Titel der Code-Aktion, z. B. "In TList&lt;TPosition&gt; umwandeln".</summary>
    Title: string;
    /// <summary>Elementtyp, wie ihn der erste Cast schreibt.</summary>
    ItemType: string;
    /// <summary>Edits der Datei mit der Deklaration.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Units; nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    /// <summary>Ohne Rückfrage anwendbar (source.fixAll): alle Typen bekannt, nur diese Datei.</summary>
    Safe: Boolean;
  end;

  /// <summary>Wandelt eine ungenerische Liste um. Ablauf: Start mit der Deklaration, für ExternalNames weitere
  /// Units über AddFile, dann Finish. Nach einem Fehlschlag nennt Reason den Grund.</summary>
  TGenericListConversion = class
  private type
    TOffsetRange = record
      StartOffset: Integer;
      EndOffset: Integer;
    end;

    TSourceFile = class
    public
      Tree: TSyntaxTree;
      OwnsTree: Boolean;
      Text: string;
      FileName: string;
      LineBreak: string;
      Edits: TArray<TTextEdit>;
      /// <summary>Offsets, an denen der generische Typ neu im Text steht.</summary>
      GenericAt: TArray<Integer>;
      /// <summary>Bereiche der alten Klassennamen, die umgeschrieben werden.</summary>
      Rewritten: TArray<TOffsetRange>;
      destructor Destroy; override;
    end;

    TElementUse = record
      FileIndex: Integer;
      Node: TSyntaxNode;
      /// <summary>Typ des Arguments; '' = unbekannt, 'nil' für nil.</summary>
      TypeName: string;
    end;

    TCastUse = record
      FileIndex: Integer;
      TypeText: string;
      Line: Integer;
    end;

    {$SCOPEDENUMS ON}
    TMatch = (No, Yes, Unknown);
    {$SCOPEDENUMS OFF}
  private
    FKind: TLegacyListKind;
    FResolver: TNameResolver;
    FFiles: TObjectList<TSourceFile>;
    FReason: string;
    FName: string;
    FOwnerType: string;
    FUnitName: string;
    FDeclaration: TSyntaxNode;
    FDeclarationLine: Integer;
    FScope: TSyntaxNode;
    FIsField: Boolean;
    FIsLocal: Boolean;
    FCreated: Boolean;
    FUnknown: Boolean;
    FProperties: TArray<string>;
    FExternalNames: TArray<string>;
    FCasts: TArray<TCastUse>;
    FElements: TArray<TElementUse>;
    function Fail(const AReason: string): Boolean;
    function Failed: Boolean;
    function NodeText(AFile: TSourceFile; ANode: TSyntaxNode): string;
    function LineOf(ANode: TSyntaxNode): string;
    function GenericText: string;
    function ItemType: string;
    procedure AddEdit(AFile: TSourceFile; const AStart, AEnd: TTextPosition; const ANewText: string);
    function IsMember(const AName: string; const AList: TArray<string>): Boolean;
    function ValueOf(const AName: string; const AList: TArray<string>; out AValue: string): Boolean;
    function IsLegacyName(ANode: TSyntaxNode): Boolean;
    function IsTypeCast(AFile: TSourceFile; ACall: TSyntaxNode; out ATypeText: string): Boolean;
    function Resolves(AFile: TSourceFile; ANode: TSyntaxNode; out ASymbol, AType: TResolvedSymbol;
      out ATypeFound: Boolean): Boolean;
    function Matches(AFileIndex: Integer; ANode: TSyntaxNode; const AName: string): TMatch;
    function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
    function LocalDeclaration(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
    function HasInlineVar(AFile: TSourceFile; ALoop: TSyntaxNode): Boolean;
    function IsOwnMethod(ANode: TSyntaxNode): Boolean;
    function VisibilityOf(AMember: TSyntaxNode): string;
    function PropertyAccessor(AFile: TSourceFile; AProperty: TSyntaxNode; const AWord: string): string;
    procedure CollectUses(AFileIndex: Integer);
    procedure ClassifyUse(AFileIndex: Integer; AUse: TSyntaxNode);
    procedure ClassifyMember(AFileIndex: Integer; AMember: TSyntaxNode);
    procedure ClassifyRead(AFileIndex: Integer; ARead: TSyntaxNode; const AWhat: string);
    procedure ClassifyLoop(AFileIndex: Integer; ALoop: TSyntaxNode);
    procedure NoteElement(AFileIndex: Integer; AArgument: TSyntaxNode);
    procedure NoteCreation(AFileIndex: Integer; AValue: TSyntaxNode);
    procedure NoteCast(AFileIndex: Integer; const ATypeText: string; ANode: TSyntaxNode);
    procedure NoteRewritten(AFile: TSourceFile; ANode: TSyntaxNode);
    procedure RemoveCast(AFile: TSourceFile; AOuter, AInner: TSyntaxNode);
    procedure RetypeDeclaration(AFile: TSourceFile; ADeclaration: TSyntaxNode; const AName, ANewType: string;
      ALegacy: Boolean);
    procedure ScanDeclaration(AFile: TSourceFile);
    procedure ScanProperties(AFile: TSourceFile; AClass: TSyntaxNode; AInterface: Boolean);
    procedure CheckElements;
    procedure AddUsesEdits(AFile: TSourceFile);
    function LegacyUnitStillUsed(AFile: TSourceFile): Boolean;
    function Finalize(AFile: TSourceFile): Boolean;
  public
    constructor Create(const AKind: TLegacyListKind; AResolver: TNameResolver);
    destructor Destroy; override;
    /// <summary>Deklaration (Field, VarDecl, InlineVar, Parameter) an APosition, z. B. an der SelectionRange des
    /// aufgelösten Symbols; AName ist der Name dort. Bei einer Property, die ein Feld derselben Klasse liest
    /// (property Items: TList read FItems), das Feld und sein Name. nil, wenn keine passt.</summary>
    class function DeclarationAt(ATree: TSyntaxTree; const APosition: TTextPosition; var AName: string): TSyntaxNode;
      static;
    /// <summary>ADeclaration ist der Field-, VarDecl- oder InlineVar-Knoten der Liste AName in ATree (gehört dem
    /// Aufrufer und muss bis Finish leben). False mit Reason, wenn die Umwandlung schon hier ausscheidet.</summary>
    function Start(ATree: TSyntaxTree; const AText, AFileName: string; ADeclaration: TSyntaxNode;
      const AName: string): Boolean;
    /// <summary>Namen, unter denen andere Units die Liste erreichen (Feld bzw. Variable und Properties); leer,
    /// wenn sie nur in dieser Unit sichtbar ist.</summary>
    function ExternalNames: TArray<string>;
    /// <summary>Weitere Unit, die einen der ExternalNames enthält; wird hier geparst.</summary>
    procedure AddFile(const AText, AFileName: string);
    /// <summary>Die Umwandlung ist nicht möglich, z. B. weil eine Unit nicht lesbar ist.</summary>
    procedure Reject(const AReason: string);
    /// <summary>Elementtyp bestimmen, Argumente prüfen, uses ergänzen. False mit Reason.</summary>
    function Finish(out APlan: TGenericListPlan): Boolean;
    /// <summary>Grund, warum die Umwandlung nicht angeboten wird; '' solange möglich.</summary>
    property Reason: string read FReason;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause;

const
  GenericUnit = 'System.Generics.Collections';
  // Platzhalter in Edits, bis der Elementtyp feststeht: generischer Typ bzw. Elementtyp.
  GenericPlaceholder = #1'G';
  ItemPlaceholder = #1'T';
  /// <summary>Mitglieder von TObject: an einer Liste ohne Typbezug, an einem Element einer Objektliste ohne Cast
  /// erlaubt.</summary>
  ObjectMembers: array[0..12] of string = ('Free', 'Destroy', 'DisposeOf', 'ClassName', 'ClassType', 'ClassInfo',
    'InstanceSize', 'InheritsFrom', 'ToString', 'GetHashCode', 'Equals', 'ClassParent', 'UnitName');
  /// <summary>Elemente dieser Typen sind keine Objekte bzw. Zeiger desselben Typs.</summary>
  ScalarTypes: array[0..21] of string = ('Pointer', 'Integer', 'Cardinal', 'NativeInt', 'NativeUInt', 'Int64',
    'UInt64', 'LongInt', 'LongWord', 'IntPtr', 'UIntPtr', 'DWORD', 'THandle', 'Byte', 'Word', 'ShortInt',
    'SmallInt', 'Int32', 'UInt32', 'PChar', 'PAnsiChar', 'PWideChar');
  /// <summary>Typen aus System.Contnrs; nennt die Unit keinen davon mehr, entfällt Contnrs aus den uses.</summary>
  ContnrsTypes: array[0..21] of string = ('TObjectList', 'TComponentList', 'TClassList', 'TOrderedList', 'TStack',
    'TQueue', 'TObjectStack', 'TObjectQueue', 'TCustomBucketList', 'TBucketList', 'TObjectBucketList',
    'TBucketItem', 'TBucketItemArray', 'TBucket', 'TBucketArray', 'TBucketProc', 'TBucketEvent',
    'TBucketListSizes', 'TListBucket', 'TBucketListBucket', 'TComponentListNexus', 'TComponentListNexusEvent');

function CommonNeutral: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := Low(ObjectMembers) to High(ObjectMembers) do
    Result := Result + [ObjectMembers[Index]];
end;

{ TLegacyListKind }

class function TLegacyListKind.PointerList: TLegacyListKind;
begin
  Result := Default(TLegacyListKind);
  Result.LegacyName := 'TList';
  Result.GenericName := 'TList';
  Result.LegacyUnit := 'Classes';
  Result.Neutral := CommonNeutral + ['Count', 'Capacity', 'Clear', 'Delete', 'Exchange', 'Move'];
  Result.Reads := ['Items', 'First', 'Last', 'Extract', 'ExtractItem'];
  Result.ElementArgs := ['Add=0', 'Insert=1', 'Extract=0', 'Remove=0', 'IndexOf=0', 'ExtractItem=0',
    'RemoveItem=0', 'IndexOfItem=0'];
  Result.Unsupported := ['Sort=Sort mit TListSortCompare', 'SortList=SortList mit TListSortCompareFunc',
    'Assign=Assign mit TListAssignOp', 'List=List-Property (PPointerList)', 'Expand=Expand',
    'Pack=Pack entfernt nil-Einträge anders', 'Grow=Grow', 'Error=Error'];
  Result.DefaultItems := True;
end;

class function TLegacyListKind.ObjectList: TLegacyListKind;
begin
  Result := PointerList;
  Result.LegacyName := 'TObjectList';
  Result.GenericName := 'TObjectList';
  Result.LegacyUnit := 'Contnrs';
  Result.Neutral := Result.Neutral + ['OwnsObjects'];
  Result.Unsupported := Result.Unsupported + ['FindInstanceOf=FindInstanceOf'];
  Result.ClassOnly := True;
end;

class function TLegacyListKind.Stack: TLegacyListKind;
begin
  Result := Default(TLegacyListKind);
  Result.LegacyName := 'TStack';
  Result.GenericName := 'TStack';
  Result.LegacyUnit := 'Contnrs';
  Result.Neutral := CommonNeutral + ['Count'];
  Result.Reads := ['Pop', 'Peek'];
  Result.ElementArgs := ['Push=0'];
  Result.Unsupported := ['AtLeast=AtLeast', 'List=List-Property (TList)'];
end;

class function TLegacyListKind.Queue: TLegacyListKind;
begin
  Result := Stack;
  Result.LegacyName := 'TQueue';
  Result.GenericName := 'TQueue';
  Result.Reads := ['Pop', 'Peek'];
  Result.Renames := ['Push=Enqueue', 'Pop=Dequeue'];
end;

class function TLegacyListKind.ObjectStack: TLegacyListKind;
begin
  Result := Stack;
  Result.LegacyName := 'TObjectStack';
  Result.GenericName := 'TObjectStack';
  // TObjectStack<T>.Pop ist eine Prozedur; Extract liefert das Element ohne Freigabe.
  Result.Renames := ['Pop=Extract'];
  // Die generischen Klassen besitzen ihre Objekte, die aus Contnrs nicht.
  Result.CreateArguments := 'False';
  Result.ClassOnly := True;
end;

class function TLegacyListKind.ObjectQueue: TLegacyListKind;
begin
  Result := ObjectStack;
  Result.LegacyName := 'TObjectQueue';
  Result.GenericName := 'TObjectQueue';
  Result.Renames := ['Push=Enqueue', 'Pop=Extract'];
end;

class function TLegacyListKind.Find(const ALegacyName: string; out AKind: TLegacyListKind): Boolean;
begin
  Result := True;
  if SameText(ALegacyName, 'TList') then
    AKind := PointerList
  else if SameText(ALegacyName, 'TObjectList') then
    AKind := ObjectList
  else if SameText(ALegacyName, 'TStack') then
    AKind := Stack
  else if SameText(ALegacyName, 'TQueue') then
    AKind := Queue
  else if SameText(ALegacyName, 'TObjectStack') then
    AKind := ObjectStack
  else if SameText(ALegacyName, 'TObjectQueue') then
    AKind := ObjectQueue
  else
  begin
    AKind := Default(TLegacyListKind);
    Result := False;
  end;
end;

{ Hilfen }

function LastName(const AText: string): string;
var
  Dot: Integer;
begin
  Result := Trim(AText);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

function IsNil(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Literal, TSyntaxKind.Identifier]) and
    SameText(ANode.Name, 'nil');
end;

function IsIdentifierNamed(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

/// <summary>Ungeklammerter Ausdruck: steigt aus ParenExpr mit genau einem Kind auf.</summary>
function Unparen(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Parent <> nil) and (Result.Parent.Kind = TSyntaxKind.ParenExpr) and
    (Result.Parent.ChildCount = 1) do
    Result := Result.Parent;
end;

function ContainsName(const ANames: string; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
    if SameText(Trim(Name), AName) then
      Exit(True);
  Result := False;
end;

function SectionOf(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    Child := ATree.Root[Index];
    if (Child.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) and
      (Child.StartOffset <= AOffset) and (Child.EndOffset >= AOffset) then
      Exit(Child);
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

{ TGenericListConversion.TSourceFile }

destructor TGenericListConversion.TSourceFile.Destroy;
begin
  if OwnsTree then
    Tree.Free;
  inherited;
end;

{ TGenericListConversion }

constructor TGenericListConversion.Create(const AKind: TLegacyListKind; AResolver: TNameResolver);
begin
  inherited Create;
  FKind := AKind;
  FResolver := AResolver;
  FFiles := TObjectList<TSourceFile>.Create(True);
end;

destructor TGenericListConversion.Destroy;
var
  Index: Integer;
begin
  // Jede Datei wurde einmal gepinnt; die Bäume erst danach freigeben.
  for Index := 0 to FFiles.Count - 1 do
    FResolver.UnpinTree;
  FFiles.Free;
  inherited;
end;

function TGenericListConversion.Fail(const AReason: string): Boolean;
begin
  if FReason = '' then
    FReason := AReason;
  Result := False;
end;

function TGenericListConversion.Failed: Boolean;
begin
  Result := FReason <> '';
end;

procedure TGenericListConversion.Reject(const AReason: string);
begin
  Fail(AReason);
end;

function TGenericListConversion.NodeText(AFile: TSourceFile; ANode: TSyntaxNode): string;
begin
  Result := Copy(AFile.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TGenericListConversion.LineOf(ANode: TSyntaxNode): string;
begin
  Result := Format('Zeile %d', [ANode.StartPos.Line + 1]);
end;

function TGenericListConversion.ItemType: string;
begin
  Result := '';
  if FCasts <> nil then
    Result := FCasts[0].TypeText;
end;

function TGenericListConversion.GenericText: string;
begin
  Result := FKind.GenericName + '<' + ItemType + '>';
end;

procedure TGenericListConversion.AddEdit(AFile: TSourceFile; const AStart, AEnd: TTextPosition;
  const ANewText: string);
begin
  AFile.Edits := AFile.Edits + [TTextEdit.Create(TTextRange.Create(AStart, AEnd), ANewText)];
end;

function TGenericListConversion.IsMember(const AName: string; const AList: TArray<string>): Boolean;
var
  Value: string;
begin
  Result := ValueOf(AName, AList, Value);
end;

function TGenericListConversion.ValueOf(const AName: string; const AList: TArray<string>;
  out AValue: string): Boolean;
var
  Entry: string;
  Separator: Integer;
begin
  AValue := '';
  for Entry in AList do
  begin
    Separator := Pos('=', Entry);
    if (Separator = 0) and SameText(Entry, AName) then
      Exit(True);
    if (Separator > 0) and SameText(Copy(Entry, 1, Separator - 1), AName) then
    begin
      AValue := Copy(Entry, Separator + 1, MaxInt);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TGenericListConversion.IsLegacyName(ANode: TSyntaxNode): Boolean;
begin
  // TList oder Unit.TList, ohne Typargumente.
  Result := False;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := SameText(ANode.Name, FKind.LegacyName)
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    Result := SameText(ANode.Name, FKind.LegacyName);
end;

function TGenericListConversion.Resolves(AFile: TSourceFile; ANode: TSyntaxNode;
  out ASymbol, AType: TResolvedSymbol; out ATypeFound: Boolean): Boolean;
begin
  try
    Result := FResolver.NodeType(AFile.Tree, AFile.FileName, ANode, ASymbol, AType, ATypeFound);
  except
    on EAbort do
      raise;
    on Exception do
    begin
      // Namensauflösung ohne Ergebnis: wie unbekannt behandeln.
      ASymbol := Default(TResolvedSymbol);
      AType := Default(TResolvedSymbol);
      ATypeFound := False;
      Result := False;
    end;
  end;
end;

function TGenericListConversion.IsTypeCast(AFile: TSourceFile; ACall: TSyntaxNode; out ATypeText: string): Boolean;
var
  Callee: TSyntaxNode;
  Symbol, SymbolType: TResolvedSymbol;
  TypeFound: Boolean;
  Name: string;
begin
  // T(X): genau ein Argument, Aufgerufener ist ein Typname (auch Unit.T).
  ATypeText := '';
  Result := False;
  if (ACall = nil) or (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount <> 2) then
    Exit;
  Callee := ACall[0];
  if not (Callee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    Exit;
  Name := LastName(NodeText(AFile, Callee));
  if MatchText(Name, ScalarTypes) or MatchText(Name, ['TObject', 'string']) then
    Result := True
  else if Resolves(AFile, Callee, Symbol, SymbolType, TypeFound) and Symbol.Found then
    Result := Symbol.IsType
  else
    // Nicht auflösbar (Typ aus einer Unit außerhalb des Index): Delphi-Konvention T… bzw. P… für Typen.
    Result := (Length(Name) >= 2) and CharInSet(Name[1], ['T', 'P']) and CharInSet(Name[2], ['A'..'Z']);
  if Result then
    ATypeText := NodeText(AFile, Callee);
end;

function TGenericListConversion.Matches(AFileIndex: Integer; ANode: TSyntaxNode; const AName: string): TMatch;
var
  SourceFile: TSourceFile;
  Symbol, SymbolType: TResolvedSymbol;
  TypeFound: Boolean;
  IsProperty: Boolean;
begin
  SourceFile := FFiles[AFileIndex];
  IsProperty := not SameText(AName, FName);
  if not Resolves(SourceFile, ANode, Symbol, SymbolType, TypeFound) or not Symbol.Found then
  begin
    // X.Name mit bekanntem Typ von X, der nicht die eigene Klasse (oder ein Nachfahre) ist: ein anderes Mitglied.
    if FIsField and (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
      Resolves(SourceFile, ANode[0], Symbol, SymbolType, TypeFound) and TypeFound and
      not SameText(LastName(SymbolType.Name), LastName(FOwnerType)) and
      FResolver.ResolveChain(SourceFile.Tree, SourceFile.FileName, [FOwnerType], ANode.StartOffset).Found and
      not FResolver.TypeDescendsFrom(SourceFile.Tree, SourceFile.FileName, ANode.StartOffset, SymbolType.Name,
      FOwnerType) then
      Exit(TMatch.No);
    Exit(TMatch.Unknown);
  end;
  if FIsLocal then
  begin
    if (Symbol.Kind = TResolvedKind.Local) and (Symbol.Range.StartPos.Line <= FDeclarationLine) and
      (Symbol.Range.EndPos.Line >= FDeclarationLine) then
      Result := TMatch.Yes
    else
      Result := TMatch.No;
    Exit;
  end;
  if FIsField then
  begin
    if (Symbol.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
      SameText(LastName(Symbol.Container), LastName(FOwnerType)) and ((AFileIndex = 0) or
      SameText(Symbol.UnitName, FUnitName)) and ((Symbol.SymbolKind = TIndexSymbolKind.Property_) = IsProperty) then
      Result := TMatch.Yes
    else
      Result := TMatch.No;
    Exit;
  end;
  // Globale Variable der Unit.
  if (Symbol.SymbolKind = TIndexSymbolKind.Variable) and (Symbol.Container = '') and
    ((AFileIndex = 0) or SameText(Symbol.UnitName, FUnitName)) then
    Result := TMatch.Yes
  else
    Result := TMatch.No;
end;

procedure TGenericListConversion.NoteCast(AFileIndex: Integer; const ATypeText: string; ANode: TSyntaxNode);
var
  Cast: TCastUse;
begin
  Cast.FileIndex := AFileIndex;
  Cast.TypeText := ATypeText;
  Cast.Line := ANode.StartPos.Line;
  FCasts := FCasts + [Cast];
end;

procedure TGenericListConversion.RemoveCast(AFile: TSourceFile; AOuter, AInner: TSyntaxNode);
begin
  // Vor und hinter dem Inneren löschen; Edits im Inneren (Umbenennungen) bleiben unberührt.
  if AOuter.StartPos <> AInner.StartPos then
    AddEdit(AFile, AOuter.StartPos, AInner.StartPos, '');
  if AInner.EndPos <> AOuter.EndPos then
    AddEdit(AFile, AInner.EndPos, AOuter.EndPos, '');
end;


procedure TGenericListConversion.NoteElement(AFileIndex: Integer; AArgument: TSyntaxNode);
var
  SourceFile: TSourceFile;
  Use: TElementUse;
  Value, Base: TSyntaxNode;
  TypeText: string;
  Symbol, SymbolType: TResolvedSymbol;
  TypeFound: Boolean;
begin
  SourceFile := FFiles[AFileIndex];
  Use.FileIndex := AFileIndex;
  Use.Node := AArgument;
  Use.TypeName := '';
  Value := AArgument;
  while (Value.Kind = TSyntaxKind.ParenExpr) and (Value.ChildCount = 1) do
    Value := Value[0];
  Base := Value;
  if (Base.Kind = TSyntaxKind.Call) and (Base.ChildCount > 0) then
    Base := Base[0];
  if IsNil(Value) then
    Use.TypeName := 'nil'
  else if IsTypeCast(SourceFile, Value, TypeText) then
    Use.TypeName := TypeText
  else if (Value.Kind = TSyntaxKind.BinaryExpr) and SameText(Value.Name, 'as') and (Value.ChildCount = 2) then
    Use.TypeName := NodeText(SourceFile, Value[1])
  else if (Base.Kind = TSyntaxKind.MemberAccess) and StartsText('Create', Base.Name) and (Base.ChildCount = 1) and
    (Base[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    // TKlasse.Create(…): der Typ steht davor. Ist es kein Typ, gilt er in CheckElements als unbekannt.
    Use.TypeName := NodeText(SourceFile, Base[0])
  else if Resolves(SourceFile, Value, Symbol, SymbolType, TypeFound) then
  begin
    if TypeFound then
      Use.TypeName := SymbolType.Name
    else
      Use.TypeName := Symbol.TypeName;
  end;
  FElements := FElements + [Use];
end;

procedure TGenericListConversion.NoteCreation(AFileIndex: Integer; AValue: TSyntaxNode);
var
  SourceFile: TSourceFile;
  Member: TSyntaxNode;
begin
  // L := TList.Create bzw. TObjectList.Create(False); jede andere Zuweisung ist eine Weitergabe.
  SourceFile := FFiles[AFileIndex];
  if IsNil(AValue) then
    Exit;
  Member := AValue;
  if (Member.Kind = TSyntaxKind.Call) and (Member.ChildCount > 0) then
    Member := Member[0];
  if (Member.Kind <> TSyntaxKind.MemberAccess) or not SameText(Member.Name, 'Create') or (Member.ChildCount <> 1) then
  begin
    Fail(Format('%s bekommt in %s einen anderen Wert als ein neues %s', [FName, LineOf(AValue),
      FKind.LegacyName]));
    Exit;
  end;
  if not IsLegacyName(Member[0]) then
  begin
    Fail(Format('%s wird in %s als %s erzeugt', [FName, LineOf(AValue), NodeText(SourceFile, Member[0])]));
    Exit;
  end;
  FCreated := True;
  NoteRewritten(SourceFile, Member[0]);
  // Der Typtext folgt in Finish, wenn T feststeht.
  AddEdit(SourceFile, Member[0].StartPos, Member[0].EndPos, GenericPlaceholder);
  if FKind.CreateArguments = '' then
    Exit;
  if AValue.Kind = TSyntaxKind.MemberAccess then
    AddEdit(SourceFile, AValue.EndPos, AValue.EndPos, '(' + FKind.CreateArguments + ')')
  else if AValue.ChildCount = 1 then
    // Create(): Argument vor die schließende Klammer.
    AddEdit(SourceFile, TTextPosition.Create(AValue.EndPos.Line, AValue.EndPos.Character - 1),
      TTextPosition.Create(AValue.EndPos.Line, AValue.EndPos.Character - 1), FKind.CreateArguments);
end;

procedure TGenericListConversion.NoteRewritten(AFile: TSourceFile; ANode: TSyntaxNode);
var
  Range: TOffsetRange;
begin
  Range.StartOffset := ANode.StartOffset;
  Range.EndOffset := ANode.EndOffset;
  AFile.Rewritten := AFile.Rewritten + [Range];
  AFile.GenericAt := AFile.GenericAt + [ANode.StartOffset];
end;

procedure TGenericListConversion.ClassifyRead(AFileIndex: Integer; ARead: TSyntaxNode; const AWhat: string);
var
  SourceFile: TSourceFile;
  Outer, Parent, Other: TSyntaxNode;
  TypeText: string;
  Symbol, SymbolType: TResolvedSymbol;
  TypeFound: Boolean;
begin
  SourceFile := FFiles[AFileIndex];
  Outer := Unparen(ARead);
  Parent := Outer.Parent;
  if Parent = nil then
    Exit;
  // T(L[I])
  if (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount = 2) and (Parent[1] = Outer) and
    IsTypeCast(SourceFile, Parent, TypeText) then
  begin
    NoteCast(AFileIndex, TypeText, Parent);
    RemoveCast(SourceFile, Parent, ARead);
    Exit;
  end;
  // L[I] as T, auch (L[I] as T).X: dann fallen die Klammern mit weg.
  if (Parent.Kind = TSyntaxKind.BinaryExpr) and SameText(Parent.Name, 'as') and (Parent.ChildCount = 2) and
    (Parent[0] = Outer) then
  begin
    NoteCast(AFileIndex, NodeText(SourceFile, Parent[1]), Parent);
    RemoveCast(SourceFile, Unparen(Parent), ARead);
    Exit;
  end;
  // Ohne Cast nur, wo der genauere Typ nichts ändert.
  if (Parent.Kind = TSyntaxKind.BinaryExpr) and MatchText(Parent.Name, ['=', '<>']) and (Parent.ChildCount = 2) then
  begin
    Other := Parent[0];
    if Other = Outer then
      Other := Parent[1];
    if IsNil(Other) then
      Exit;
  end;
  if (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount = 2) and IsIdentifierNamed(Parent[0], 'Assigned') then
    Exit;
  if FKind.ClassOnly and (Parent.Kind = TSyntaxKind.MemberAccess) and MatchText(Parent.Name, ObjectMembers) then
    Exit;
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount = 2) and (Parent[1] = Outer) and
    Resolves(SourceFile, Parent[0], Symbol, SymbolType, TypeFound) and TypeFound and
    SameText(SymbolType.Name, 'Pointer') then
    Exit;
  Fail(Format('%s wird in %s ohne Cast gelesen', [AWhat, LineOf(ARead)]));
end;

procedure TGenericListConversion.ClassifyMember(AFileIndex: Integer; AMember: TSyntaxNode);
var
  SourceFile: TSourceFile;
  Name, Value: string;
  Parent, Call, Read: TSyntaxNode;
  Position: Integer;
begin
  SourceFile := FFiles[AFileIndex];
  Name := AMember.Name;
  Parent := AMember.Parent;
  Call := nil;
  if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount > 0) and (Parent[0] = AMember) then
    Call := Parent;
  if ValueOf(Name, FKind.Unsupported, Value) then
  begin
    Fail(Format('%s hat in %s<T> kein Gegenstück (%s, %s)', [Value, FKind.GenericName, FName, LineOf(AMember)]));
    Exit;
  end;
  if not IsMember(Name, FKind.Neutral) and not IsMember(Name, FKind.Reads) and
    not IsMember(Name, FKind.ElementArgs) then
  begin
    Fail(Format('%s.%s hat in %s<T> kein Gegenstück (%s)', [FName, Name, FKind.GenericName, LineOf(AMember)]));
    Exit;
  end;
  // Umbenennen: der Name ist das letzte Wort des MemberAccess (L.Push → L.Enqueue).
  if ValueOf(Name, FKind.Renames, Value) and (AMember.EndPos.Character >= Length(Name)) then
    AddEdit(SourceFile, TTextPosition.Create(AMember.EndPos.Line, AMember.EndPos.Character - Length(Name)),
      AMember.EndPos, Value);
  // Count ist in TOrderedList (Contnrs) eine Funktion, generisch eine Property: Count() ohne Klammern.
  if (Call <> nil) and (Call.ChildCount = 1) and SameText(Name, 'Count') then
    AddEdit(SourceFile, AMember.EndPos, Call.EndPos, '');
  if ValueOf(Name, FKind.ElementArgs, Value) then
  begin
    Position := StrToIntDef(Value, 0);
    if (Call <> nil) and (Call.ChildCount > Position + 1) then
      NoteElement(AFileIndex, Call[Position + 1]);
  end;
  if not IsMember(Name, FKind.Reads) then
    Exit;
  Read := AMember;
  if Call <> nil then
    Read := Call
  else if (Parent <> nil) and (Parent.Kind = TSyntaxKind.IndexAccess) and (Parent[0] = AMember) then
  begin
    Read := Parent;
    // L.Items[I] := X
    if (Read.Parent <> nil) and (Read.Parent.Kind = TSyntaxKind.AssignStatement) and
      (Read.Parent.ChildCount = 2) and (Read.Parent[0] = Read) then
    begin
      NoteElement(AFileIndex, Read.Parent[1]);
      Exit;
    end;
  end;
  // Ergebnis verworfen: L.Pop; bzw. L.Extract(X);
  if (Read.Parent <> nil) and (Read.Parent.Kind = TSyntaxKind.CallStatement) then
    Exit;
  ClassifyRead(AFileIndex, Read, FName);
end;

function TGenericListConversion.EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    Result := Result.Parent;
end;

function TGenericListConversion.LocalDeclaration(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index, Inner: Integer;
  Child: TSyntaxNode;
begin
  // Nur der var-Abschnitt der Routine selbst; Parameter, Felder und globale Variablen zählen nicht.
  Result := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Child := ARoutine[Index];
    if Child.Kind <> TSyntaxKind.VarSection then
      Continue;
    for Inner := 0 to Child.ChildCount - 1 do
      if (Child[Inner].Kind = TSyntaxKind.VarDecl) and ContainsName(Child[Inner].Name, AName) then
        Exit(Child[Inner]);
  end;
end;

function TGenericListConversion.HasInlineVar(AFile: TSourceFile; ALoop: TSyntaxNode): Boolean;
var
  Index: Integer;
  Tokens: TArray<TPascalToken>;
  Seen: Integer;
begin
  // for var V in …: das Wort hinter for ist var.
  Tokens := AFile.Tree.Tokens;
  Seen := 0;
  for Index := TSyntaxTree.FirstTokenOf(Tokens, ALoop.StartOffset) to High(Tokens) do
  begin
    if Tokens[Index].Offset < ALoop.StartOffset then
      Continue;
    if IsTrivia(Tokens[Index]) then
      Continue;
    Inc(Seen);
    if Seen = 2 then
      Exit(Tokens[Index].IsKeyword('var'));
  end;
  Result := False;
end;

procedure TGenericListConversion.ClassifyLoop(AFileIndex: Integer; ALoop: TSyntaxNode);
var
  SourceFile: TSourceFile;
  Name: string;
  TypeRef, Routine, Declaration, Scope: TSyntaxNode;
  IsInline: Boolean;
  Visit: TSyntaxNodeVisit;
begin
  // for V in L do: V bekommt den Typ T, Casts auf V entfallen.
  SourceFile := FFiles[AFileIndex];
  Name := ALoop.Name;
  TypeRef := ALoop.FindChild(TSyntaxKind.TypeReference);
  IsInline := (TypeRef <> nil) or HasInlineVar(SourceFile, ALoop);
  Scope := ALoop;
  if TypeRef <> nil then
    AddEdit(SourceFile, TypeRef.StartPos, TypeRef.EndPos, ItemPlaceholder)
  else if not IsInline then
  begin
    Routine := EnclosingRoutine(ALoop);
    Declaration := nil;
    if Routine <> nil then
      Declaration := LocalDeclaration(Routine, Name);
    if Declaration = nil then
    begin
      Fail(Format('Die Schleifenvariable %s in %s ist keine lokale Variable', [Name, LineOf(ALoop)]));
      Exit;
    end;
    RetypeDeclaration(SourceFile, Declaration, Name, ItemPlaceholder, False);
    Scope := Routine;
  end;
  Visit :=
    function(ANode: TSyntaxNode): Boolean
    var
      Parent: TSyntaxNode;
    begin
      Result := not Failed;
      if not Result then
        Exit;
      if (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and (ANode <> ALoop) and
        SameText(ANode.Name, Name) then
      begin
        Fail(Format('Die Schleifenvariable %s wird in %s auch anders benutzt', [Name, LineOf(ANode)]));
        Exit(False);
      end;
      if not IsIdentifierNamed(ANode, Name) then
        Exit;
      Parent := Unparen(ANode).Parent;
      if (Parent <> nil) and (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Unparen(ANode)) then
      begin
        Fail(Format('Der Schleifenvariable %s wird in %s etwas zugewiesen', [Name, LineOf(ANode)]));
        Exit(False);
      end;
      ClassifyRead(AFileIndex, ANode, Name);
    end;
  Scope.Walk(Visit);
end;

procedure TGenericListConversion.ClassifyUse(AFileIndex: Integer; AUse: TSyntaxNode);
var
  Parent, Read, Other, Collection: TSyntaxNode;
  Index: Integer;
begin
  Parent := AUse.Parent;
  if Parent = nil then
    Exit;
  case Parent.Kind of
    TSyntaxKind.AssignStatement:
      if (Parent.ChildCount = 2) and (Parent[0] = AUse) then
        NoteCreation(AFileIndex, Parent[1])
      else
        Fail(Format('%s wird in %s weitergegeben', [FName, LineOf(AUse)]));
    TSyntaxKind.MemberAccess:
      if Parent[0] = AUse then
        ClassifyMember(AFileIndex, Parent)
      else
        Fail(Format('Nicht unterstützte Verwendung von %s in %s', [FName, LineOf(AUse)]));
    TSyntaxKind.IndexAccess:
      if (Parent[0] = AUse) and FKind.DefaultItems then
      begin
        Read := Parent;
        if (Read.Parent <> nil) and (Read.Parent.Kind = TSyntaxKind.AssignStatement) and
          (Read.Parent.ChildCount = 2) and (Read.Parent[0] = Read) then
          NoteElement(AFileIndex, Read.Parent[1])
        else
          ClassifyRead(AFileIndex, Read, FName);
      end
      else
        Fail(Format('Nicht unterstützte Verwendung von %s in %s', [FName, LineOf(AUse)]));
    TSyntaxKind.ForInStatement:
      begin
        Collection := nil;
        for Index := 0 to Parent.ChildCount - 1 do
          if Parent[Index].Kind <> TSyntaxKind.TypeReference then
          begin
            Collection := Parent[Index];
            Break;
          end;
        if Collection = AUse then
          ClassifyLoop(AFileIndex, Parent)
        else
          Fail(Format('Nicht unterstützte Verwendung von %s in %s', [FName, LineOf(AUse)]));
      end;
    TSyntaxKind.Call:
      if (Parent[0] <> AUse) and (IsIdentifierNamed(Parent[0], 'FreeAndNil') or
        IsIdentifierNamed(Parent[0], 'Assigned')) then
        Exit
      else
        Fail(Format('%s wird in %s an %s übergeben', [FName, LineOf(AUse), NodeText(FFiles[AFileIndex],
          Parent[0])]));
    TSyntaxKind.BinaryExpr:
      begin
        Other := nil;
        if MatchText(Parent.Name, ['=', '<>']) and (Parent.ChildCount = 2) then
        begin
          Other := Parent[0];
          if Other = AUse then
            Other := Parent[1];
        end;
        if not IsNil(Other) then
          Fail(Format('Nicht unterstützte Verwendung von %s in %s', [FName, LineOf(AUse)]));
      end;
    TSyntaxKind.WithStatement:
      Fail(Format('%s steht in %s in einer with-Anweisung', [FName, LineOf(AUse)]));
  else
    Fail(Format('%s wird in %s weitergegeben', [FName, LineOf(AUse)]));
  end;
end;

function TGenericListConversion.IsOwnMethod(ANode: TSyntaxNode): Boolean;
var
  Routine: TSyntaxNode;
begin
  // Bezeichner in einer Methode der eigenen Klasse (TKlasse.Methode), auch in einer lokalen Routine darin.
  Routine := EnclosingRoutine(ANode);
  while Routine <> nil do
  begin
    if StartsText(LastName(FOwnerType) + '.', Routine.Name) then
      Exit(True);
    Routine := EnclosingRoutine(Routine);
  end;
  Result := False;
end;

procedure TGenericListConversion.CollectUses(AFileIndex: Integer);
var
  SourceFile: TSourceFile;
  Names: TArray<string>;
  Visit: TSyntaxNodeVisit;
begin
  SourceFile := FFiles[AFileIndex];
  if AFileIndex = 0 then
    Names := [FName] + FProperties
  else
    Names := ExternalNames;
  Visit :=
    function(ANode: TSyntaxNode): Boolean
    var
      Match: TMatch;
      Assumed: Boolean;
    begin
      Result := not Failed;
      if not Result then
        Exit;
      if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
        not MatchText(ANode.Name, Names) then
        Exit;
      // Mitglied der Liste selbst (L.Items, wenn eine Property der Klasse auch Items heißt).
      if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
        (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
        MatchText(ANode[0].Name, Names) and MatchText(ANode.Name, FKind.Reads + FKind.Neutral) then
        Exit;
      Match := Matches(AFileIndex, ANode, ANode.Name);
      if Match = TMatch.Unknown then
      begin
        // Ohne Index (Linter, Tests) in der eigenen Datei: lokale Variable der Routine bzw. Feld in einer Methode
        // der eigenen Klasse oder über Self.
        Assumed := False;
        if AFileIndex = 0 then
        begin
          if FIsLocal then
            Assumed := (ANode.Kind = TSyntaxKind.Identifier) and (FScope <> nil) and
              (ANode.StartOffset >= FScope.StartOffset) and (ANode.EndOffset <= FScope.EndOffset)
          else if FIsField then
            Assumed := ((ANode.Kind = TSyntaxKind.Identifier) and IsOwnMethod(ANode)) or
              ((ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
              IsIdentifierNamed(ANode[0], 'Self') and IsOwnMethod(ANode))
          else
            Assumed := ANode.Kind = TSyntaxKind.Identifier;
        end;
        if not Assumed then
        begin
          Fail(Format('Die Verwendung von %s in %s (%s) ist nicht auflösbar', [ANode.Name,
            ExtractFileName(SourceFile.FileName), LineOf(ANode)]));
          Exit(False);
        end;
        Match := TMatch.Yes;
      end;
      if Match = TMatch.Yes then
      begin
        ClassifyUse(AFileIndex, ANode);
        // Die Kinder (Self, A in A.FListe) sind keine weiteren Verwendungen.
        Exit(False);
      end;
    end;
  SourceFile.Tree.Root.Walk(Visit);
end;

procedure TGenericListConversion.RetypeDeclaration(AFile: TSourceFile; ADeclaration: TSyntaxNode;
  const AName, ANewType: string; ALegacy: Boolean);
var
  TypeRef: TSyntaxNode;
  Others: TArray<string>;
  Name, Rest, Indent: string;
begin
  TypeRef := ADeclaration.FindChild(TSyntaxKind.TypeReference);
  if TypeRef = nil then
    Exit;
  if Pos(',', ADeclaration.Name) = 0 then
  begin
    if ALegacy then
      NoteRewritten(AFile, TypeRef);
    AddEdit(AFile, TypeRef.StartPos, TypeRef.EndPos, ANewType);
    Exit;
  end;
  // A, L, B: TList; → A, B: TList; und L: TList<T>; in einer eigenen Zeile.
  if not EndsText(';', Trim(Copy(AFile.Text, TypeRef.StartOffset + 1, ADeclaration.EndOffset -
    TypeRef.StartOffset))) then
  begin
    Fail(Format('%s steht in %s mit weiteren Namen in einer Deklaration', [AName, LineOf(ADeclaration)]));
    Exit;
  end;
  Others := nil;
  for Name in SplitString(ADeclaration.Name, ',') do
    if not SameText(Trim(Name), AName) then
      Others := Others + [Trim(Name)];
  Rest := Copy(AFile.Text, TypeRef.StartOffset + 1, ADeclaration.EndOffset - TypeRef.StartOffset);
  Indent := StringOfChar(' ', ADeclaration.StartPos.Character);
  if ALegacy then
    AFile.GenericAt := AFile.GenericAt + [ADeclaration.StartOffset];
  AddEdit(AFile, ADeclaration.StartPos, ADeclaration.EndPos, string.Join(', ', Others) + ': ' + Rest +
    AFile.LineBreak + Indent + AName + ': ' + ANewType + ';');
end;

function TGenericListConversion.VisibilityOf(AMember: TSyntaxNode): string;
var
  Parent: TSyntaxNode;
  Index: Integer;
begin
  // Letzter Sichtbarkeitsabschnitt davor; ohne Angabe published (Klassen) bzw. public (Records).
  Result := 'public';
  Parent := AMember.Parent;
  if Parent = nil then
    Exit;
  for Index := 0 to Parent.ChildCount - 1 do
  begin
    if Parent[Index] = AMember then
      Break;
    if Parent[Index].Kind = TSyntaxKind.Visibility then
      Result := LowerCase(Parent[Index].Name);
  end;
end;

function TGenericListConversion.PropertyAccessor(AFile: TSourceFile; AProperty: TSyntaxNode;
  const AWord: string): string;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  // Wort hinter read bzw. write aus den Token der Property; '' ohne.
  Result := '';
  Tokens := AFile.Tree.Tokens;
  for Index := TSyntaxTree.FirstTokenOf(Tokens, AProperty.StartOffset) to High(Tokens) - 1 do
  begin
    if (Tokens[Index].Offset < AProperty.StartOffset) or (Tokens[Index].Offset >= AProperty.EndOffset) then
      Continue;
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AWord) and
      (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
      Exit(Tokens[Index + 1].Text);
  end;
end;

procedure TGenericListConversion.ScanProperties(AFile: TSourceFile; AClass: TSyntaxNode; AInterface: Boolean);
var
  Index: Integer;
  Member, TypeRef: TSyntaxNode;
  ReadName, WriteName: string;
begin
  // property Items: TList read FItems: die Property wird mit umgewandelt; ein Getter oder Setter verhindert es.
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    Member := AClass[Index];
    if Member.Kind <> TSyntaxKind.PropertyDecl then
      Continue;
    TypeRef := Member.FindChild(TSyntaxKind.TypeReference);
    ReadName := PropertyAccessor(AFile, Member, 'read');
    WriteName := PropertyAccessor(AFile, Member, 'write');
    if not SameText(ReadName, FName) and not SameText(WriteName, FName) then
      Continue;
    if (TypeRef = nil) or (TypeRef.ChildCount > 0) or not SameText(LastName(TypeRef.Name), FKind.LegacyName) then
    begin
      Fail(Format('Die Property %s in %s hat einen anderen Typ', [Member.Name, LineOf(Member)]));
      Exit;
    end;
    if (ReadName <> '') and not SameText(ReadName, FName) then
    begin
      Fail(Format('Die Property %s liest über %s', [Member.Name, ReadName]));
      Exit;
    end;
    if (WriteName <> '') and not SameText(WriteName, FName) then
    begin
      Fail(Format('Die Property %s schreibt über %s', [Member.Name, WriteName]));
      Exit;
    end;
    if (Member.ChildCount > 1) and (Member.FindChild(TSyntaxKind.Parameters) <> nil) then
    begin
      Fail(Format('Die Property %s hat Indexparameter', [Member.Name]));
      Exit;
    end;
    FProperties := FProperties + [Member.Name];
    if AInterface and (Pos('private', VisibilityOf(Member)) = 0) then
      FExternalNames := FExternalNames + [Member.Name];
    NoteRewritten(AFile, TypeRef);
    AddEdit(AFile, TypeRef.StartPos, TypeRef.EndPos, GenericPlaceholder);
  end;
end;

procedure TGenericListConversion.ScanDeclaration(AFile: TSourceFile);
var
  Declaration, Owner, TypeDecl, Section, Value: TSyntaxNode;
  InInterface: Boolean;
begin
  Declaration := FDeclaration;
  Owner := Declaration.Parent;
  case Declaration.Kind of
    TSyntaxKind.Field:
      begin
        while (Owner <> nil) and not (Owner.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType,
          TSyntaxKind.ObjectType]) do
          Owner := Owner.Parent;
        TypeDecl := Owner;
        while (TypeDecl <> nil) and (TypeDecl.Kind <> TSyntaxKind.TypeDecl) do
          TypeDecl := TypeDecl.Parent;
        if (Owner = nil) or (TypeDecl = nil) then
        begin
          Fail(Format('Die Klasse zu %s ist nicht erkennbar', [FName]));
          Exit;
        end;
        FIsField := True;
        FOwnerType := TypeDecl.Name;
        Section := SectionOf(AFile.Tree, Declaration.StartOffset);
        InInterface := (Section <> nil) and (Section.Kind = TSyntaxKind.InterfaceSection);
        if InInterface and (Pos('private', VisibilityOf(Declaration)) = 0) then
          FExternalNames := FExternalNames + [FName];
        RetypeDeclaration(AFile, Declaration, FName, GenericPlaceholder, True);
        if not Failed then
          ScanProperties(AFile, Owner, InInterface);
      end;
    TSyntaxKind.VarDecl:
      begin
        FScope := EnclosingRoutine(Declaration);
        FIsLocal := FScope <> nil;
        Section := SectionOf(AFile.Tree, Declaration.StartOffset);
        if not FIsLocal and (Section <> nil) and (Section.Kind = TSyntaxKind.InterfaceSection) then
          FExternalNames := FExternalNames + [FName];
        RetypeDeclaration(AFile, Declaration, FName, GenericPlaceholder, True);
      end;
    TSyntaxKind.InlineVar:
      begin
        FScope := EnclosingRoutine(Declaration);
        FIsLocal := True;
        if Pos(',', Declaration.Name) > 0 then
        begin
          Fail(Format('%s steht in %s mit weiteren Namen in einer Inline-Variable', [FName, LineOf(Declaration)]));
          Exit;
        end;
        RetypeDeclaration(AFile, Declaration, FName, GenericPlaceholder, True);
        Value := nil;
        if (Declaration.ChildCount > 0) and (Declaration[Declaration.ChildCount - 1].Kind <>
          TSyntaxKind.TypeReference) then
          Value := Declaration[Declaration.ChildCount - 1];
        if Value <> nil then
          NoteCreation(0, Value);
      end;
    TSyntaxKind.Parameter:
      Fail(Format('%s ist ein Parameter; die Signatur der Routine müsste sich ändern', [FName]));
  else
    Fail(Format('%s ist keine Variable und kein Feld', [FName]));
  end;
end;

/// <summary>Liegt A vor B (oder auf B)?</summary>
function NotAfter(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Bezeichner hinter dem Wort AWord in den Token von ANode, z. B. das Feld hinter read; '' ohne.</summary>
function IdentifierAfter(ATree: TSyntaxTree; ANode: TSyntaxNode; const AWord: string): string;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Result := '';
  Tokens := ATree.Tokens;
  for Index := TSyntaxTree.FirstTokenOf(Tokens, ANode.StartOffset) to High(Tokens) - 1 do
    if (Tokens[Index].Offset >= ANode.StartOffset) and (Tokens[Index].Offset < ANode.EndOffset) and
      (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AWord) and
      (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
      Exit(Tokens[Index + 1].Text);
end;

class function TGenericListConversion.DeclarationAt(ATree: TSyntaxTree; const APosition: TTextPosition;
  var AName: string): TSyntaxNode;
var
  Found, Member: TSyntaxNode;
  FieldName: string;
  Index: Integer;

  procedure Visit(ANode: TSyntaxNode);
  var
    Child: Integer;
  begin
    if not NotAfter(ANode.StartPos, APosition) or not NotAfter(APosition, ANode.EndPos) then
      Exit;
    if ANode.Kind in [TSyntaxKind.Field, TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
      TSyntaxKind.PropertyDecl] then
      Found := ANode;
    for Child := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Child]);
  end;

begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Found := nil;
  Visit(ATree.Root);
  // Der Name muss an der Stelle stehen; sonst passt die Position nicht zum Text (veralteter Index).
  if (Found = nil) or not MatchText(AName, SplitString(Found.Name, ', ')) then
    Exit;
  if Found.Kind <> TSyntaxKind.PropertyDecl then
    Exit(Found);
  // Property mit read-Feld: umgewandelt wird das Feld, die Property folgt ihm (ScanProperties).
  FieldName := IdentifierAfter(ATree, Found, 'read');
  if (FieldName = '') or (Found.Parent = nil) then
    Exit;
  for Index := 0 to Found.Parent.ChildCount - 1 do
  begin
    Member := Found.Parent[Index];
    if (Member.Kind = TSyntaxKind.Field) and MatchText(FieldName, SplitString(Member.Name, ', ')) then
    begin
      AName := FieldName;
      Exit(Member);
    end;
  end;
end;

function TGenericListConversion.Start(ATree: TSyntaxTree; const AText, AFileName: string;
  ADeclaration: TSyntaxNode; const AName: string): Boolean;
var
  SourceFile: TSourceFile;
begin
  SourceFile := TSourceFile.Create;
  SourceFile.Tree := ATree;
  SourceFile.Text := AText;
  SourceFile.FileName := AFileName;
  SourceFile.LineBreak := TTextLines.LineBreakOf(AText);
  FFiles.Add(SourceFile);
  FResolver.PinTree(ATree, AFileName);
  FDeclaration := ADeclaration;
  FDeclarationLine := ADeclaration.StartPos.Line;
  FName := AName;
  FUnitName := TUsesClauses.OwnName(ATree.Tokens);
  ScanDeclaration(SourceFile);
  if not Failed then
    CollectUses(0);
  Result := not Failed;
end;

function TGenericListConversion.ExternalNames: TArray<string>;
begin
  Result := FExternalNames;
end;

procedure TGenericListConversion.AddFile(const AText, AFileName: string);
var
  SourceFile: TSourceFile;
begin
  if Failed then
    Exit;
  SourceFile := TSourceFile.Create;
  SourceFile.Tree := TSyntaxTreeCache.Parse(AText);
  SourceFile.OwnsTree := True;
  SourceFile.Text := AText;
  SourceFile.FileName := AFileName;
  SourceFile.LineBreak := TTextLines.LineBreakOf(AText);
  FFiles.Add(SourceFile);
  FResolver.PinTree(SourceFile.Tree, AFileName);
  CollectUses(FFiles.Count - 1);
end;

procedure TGenericListConversion.CheckElements;
var
  Use: TElementUse;
  SourceFile: TSourceFile;
  Actual, Target: TResolvedSymbol;
  ItemName: string;
begin
  ItemName := LastName(ItemType);
  for Use in FElements do
  begin
    if Failed then
      Exit;
    if Use.TypeName = 'nil' then
      Continue;
    if Use.TypeName = '' then
    begin
      FUnknown := True;
      Continue;
    end;
    if MatchText(LastName(Use.TypeName), ScalarTypes) then
    begin
      Fail(Format('%s nimmt in %s Werte vom Typ %s auf', [FName, LineOf(Use.Node), LastName(Use.TypeName)]));
      Exit;
    end;
    if SameText(LastName(Use.TypeName), ItemName) then
      Continue;
    // Nachfahre von T? Beide Namen so aufgelöst, wie sie an der Stelle stehen.
    SourceFile := FFiles[Use.FileIndex];
    Actual := FResolver.ResolveChain(SourceFile.Tree, SourceFile.FileName, Use.TypeName.Split(['.']),
      Use.Node.StartOffset);
    Target := FResolver.ResolveChain(SourceFile.Tree, SourceFile.FileName, ItemType.Split(['.']),
      Use.Node.StartOffset);
    if Actual.Found and Actual.IsType and Target.Found and Target.IsType then
    begin
      if not FResolver.TypeDescendsFrom(SourceFile.Tree, SourceFile.FileName, Use.Node.StartOffset, Use.TypeName,
        ItemType) then
        Fail(Format('%s nimmt in %s Werte vom Typ %s auf, nicht %s', [FName, LineOf(Use.Node),
          Use.TypeName, ItemType]));
    end
    else
      FUnknown := True;
  end;
end;

function TGenericListConversion.LegacyUnitStillUsed(AFile: TSourceFile): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Range: TOffsetRange;
  Inside: Boolean;
begin
  Tokens := AFile.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not MatchText(Tokens[Index].Text, ContnrsTypes) then
      Continue;
    Inside := False;
    for Range in AFile.Rewritten do
      if (Tokens[Index].Offset >= Range.StartOffset) and (Tokens[Index].Offset < Range.EndOffset) then
        Inside := True;
    if Inside then
      Continue;
    // TStack<T> und TObjectList<T> stammen aus System.Generics.Collections.
    Next := Index + 1;
    while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
      Inc(Next);
    if (Next <= High(Tokens)) and Tokens[Next].IsSymbol('<') then
      Continue;
    Exit(True);
  end;
  Result := False;
end;

procedure TGenericListConversion.AddUsesEdits(AFile: TSourceFile);
type
  TItem = record
    Name: string;
    Text: string;
    FirstToken: Integer;
    LastToken: Integer;
  end;
var
  Tokens: TArray<TPascalToken>;
  Clauses: TArray<TUsesClauseInfo>;
  Clause: TUsesClauseInfo;
  Items, Kept: TArray<TItem>;
  Item: TItem;
  Namespaces: TArray<string>;
  Implementation_: TSyntaxNode;
  ImplementationStart, Offset, Index, Cursor, AddAt: Integer;
  NeedInterface, NeedGeneric, InInterface, InImplementation, DropLegacy, MoveGeneric, AddHere, IsUnit,
    Removed: Boolean;
  Target: Integer;
  Separator, NewText: string;
  Edit: TTextEdit;

  function IsLegacyUnit(const AName: string): Boolean;
  begin
    Result := SameText(AName, FKind.LegacyUnit) or SameText(AName, 'System.' + FKind.LegacyUnit);
  end;

  function IsGenericUnit(const AName: string): Boolean;
  begin
    Result := TUsesClauses.IsUsed([AName], GenericUnit, Namespaces);
  end;

begin
  Tokens := AFile.Tree.Tokens;
  Namespaces := FResolver.Namespaces;
  Clauses := TUsesClauses.Clauses(Tokens);
  IsUnit := AFile.Tree.Root.Kind = TSyntaxKind.UnitFile;
  Implementation_ := AFile.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  ImplementationStart := MaxInt;
  if Implementation_ <> nil then
    ImplementationStart := Implementation_.StartOffset;
  NeedGeneric := AFile.GenericAt <> nil;
  NeedInterface := False;
  for Offset in AFile.GenericAt do
    if IsUnit and (Offset < ImplementationStart) then
      NeedInterface := True;
  InInterface := False;
  InImplementation := False;
  for Clause in Clauses do
    for Index := 0 to High(Clause.Names) do
      if IsGenericUnit(Clause.Names[Index]) then
      begin
        if Clause.InInterface or not IsUnit then
          InInterface := True
        else
          InImplementation := True;
      end;
  DropLegacy := (FKind.LegacyUnit = 'Contnrs') and (AFile.Rewritten <> nil) and not LegacyUnitStillUsed(AFile);
  MoveGeneric := NeedInterface and InImplementation and not InInterface;
  AddHere := NeedGeneric and not InInterface and not (InImplementation and not NeedInterface);
  // Zielliste für System.Generics.Collections: interface, wenn der Typ dort steht, sonst die des Abschnitts.
  Target := -1;
  if AddHere then
    for Index := 0 to High(Clauses) do
      if not IsUnit or (Clauses[Index].InInterface = NeedInterface) then
      begin
        Target := Index;
        Break;
      end;
  for Index := 0 to High(Clauses) do
  begin
    Clause := Clauses[Index];
    // Einträge der Liste mit ihrem Quelltext; Trennzeichen sind die Kommas.
    Items := nil;
    Cursor := Clause.UsesIndex + 1;
    while Cursor < Clause.Semicolon do
    begin
      while (Cursor < Clause.Semicolon) and IsTrivia(Tokens[Cursor]) do
        Inc(Cursor);
      if Cursor >= Clause.Semicolon then
        Break;
      Item.FirstToken := Cursor;
      Item.LastToken := Cursor;
      Item.Name := '';
      while (Cursor < Clause.Semicolon) and not Tokens[Cursor].IsSymbol(',') do
      begin
        if Tokens[Cursor].IsKeyword('in') then
          Item.Name := Item.Name + ' '
        else if (Pos(' ', Item.Name) = 0) and ((Tokens[Cursor].Kind = TPascalTokenKind.Identifier) or
          Tokens[Cursor].IsSymbol('.')) then
          Item.Name := Item.Name + Tokens[Cursor].Text;
        if not IsTrivia(Tokens[Cursor]) then
          Item.LastToken := Cursor;
        Inc(Cursor);
      end;
      Item.Name := Trim(Item.Name);
      Item.Text := Copy(AFile.Text, Tokens[Item.FirstToken].Offset + 1, Tokens[Item.LastToken].Offset +
        Length(Tokens[Item.LastToken].Text) - Tokens[Item.FirstToken].Offset);
      Items := Items + [Item];
      Inc(Cursor);
    end;
    Kept := nil;
    AddAt := -1;
    for Item in Items do
      if (DropLegacy and IsLegacyUnit(Item.Name)) or (MoveGeneric and IsUnit and not Clause.InInterface and
        IsGenericUnit(Item.Name)) then
      begin
        if AddAt < 0 then
          AddAt := Length(Kept);
      end
      else
        Kept := Kept + [Item];
    if (Length(Kept) = Length(Items)) and (Index <> Target) and not (MoveGeneric and Clause.InInterface) then
      Continue;
    Removed := Length(Kept) <> Length(Items);
    if Removed then
    begin
      if not Clause.Plain then
      begin
        // Listen mit Direktiven oder Kommentaren bleiben unangetastet; Contnrs bleibt dann stehen.
        if MoveGeneric then
          Fail(Format('%s steht nur im implementation-uses (Liste mit Direktiven)', [GenericUnit]));
        Kept := Items;
        AddAt := -1;
        Removed := False;
      end;
    end;
    NewText := '';
    if (Index = Target) or (MoveGeneric and Clause.InInterface) then
    begin
      Item := Default(TItem);
      Item.Text := GenericUnit;
      if (AddAt < 0) or (AddAt > Length(Kept)) then
        AddAt := Length(Kept);
      Insert(Item, Kept, AddAt);
    end;
    if not Removed then
    begin
      // Nur ergänzen: hinter den letzten Eintrag wie TUsesClauses.AddUnit.
      if TUsesClauses.AddUnit(Tokens, Tokens[Clause.UsesIndex].Offset + 1, GenericUnit, AFile.LineBreak, Edit) then
        AFile.Edits := AFile.Edits + [Edit];
      Continue;
    end;
    if Kept = nil then
    begin
      AddEdit(AFile, Tokens[Clause.UsesIndex].StartPos, Tokens[Clause.Semicolon].EndPos, '');
      Continue;
    end;
    if Tokens[Items[High(Items)].LastToken].StartPos.Line > Tokens[Clause.UsesIndex].StartPos.Line then
      Separator := ',' + AFile.LineBreak + StringOfChar(' ', Tokens[Items[0].FirstToken].StartPos.Character)
    else
      Separator := ', ';
    for Item in Kept do
    begin
      if NewText <> '' then
        NewText := NewText + Separator;
      NewText := NewText + Item.Text;
    end;
    AddEdit(AFile, Tokens[Items[0].FirstToken].StartPos, Tokens[Items[High(Items)].LastToken].EndPos, NewText);
  end;
  // Noch kein uses im Abschnitt: neues uses hinter interface bzw. implementation.
  if AddHere and (Target < 0) and not (MoveGeneric and InInterface) then
  begin
    Offset := AFile.GenericAt[0];
    if NeedInterface then
      for Index := 0 to High(AFile.GenericAt) do
        if AFile.GenericAt[Index] < ImplementationStart then
        begin
          Offset := AFile.GenericAt[Index];
          Break;
        end;
    if TUsesClauses.AddUnit(Tokens, Offset, GenericUnit, AFile.LineBreak, Edit) then
      AFile.Edits := AFile.Edits + [Edit];
  end;
end;

function EditBefore(const A, B: TTextEdit): Boolean;
begin
  Result := (A.Range.StartPos.Line < B.Range.StartPos.Line) or ((A.Range.StartPos.Line = B.Range.StartPos.Line) and
    (A.Range.StartPos.Character < B.Range.StartPos.Character));
end;

function TGenericListConversion.Finalize(AFile: TSourceFile): Boolean;
var
  Index, Inner: Integer;
  Edit: TTextEdit;
  Edits: TArray<TTextEdit>;
  Before, After: TTextPosition;
begin
  // Platzhalter einsetzen, sortieren, doppelte entfernen und Überlappungen ausschließen.
  Edits := nil;
  for Edit in AFile.Edits do
    Edits := Edits + [TTextEdit.Create(Edit.Range, StringReplace(StringReplace(Edit.NewText, GenericPlaceholder,
      GenericText, [rfReplaceAll]), ItemPlaceholder, ItemType, [rfReplaceAll]))];
  for Index := 1 to High(Edits) do
  begin
    Edit := Edits[Index];
    Inner := Index - 1;
    while (Inner >= 0) and EditBefore(Edit, Edits[Inner]) do
    begin
      Edits[Inner + 1] := Edits[Inner];
      Dec(Inner);
    end;
    Edits[Inner + 1] := Edit;
  end;
  AFile.Edits := nil;
  for Index := 0 to High(Edits) do
  begin
    if (AFile.Edits <> nil) and (AFile.Edits[High(AFile.Edits)].Range.StartPos = Edits[Index].Range.StartPos) and
      (AFile.Edits[High(AFile.Edits)].Range.EndPos = Edits[Index].Range.EndPos) and
      (AFile.Edits[High(AFile.Edits)].NewText = Edits[Index].NewText) then
      Continue;
    if AFile.Edits <> nil then
    begin
      Before := AFile.Edits[High(AFile.Edits)].Range.EndPos;
      After := Edits[Index].Range.StartPos;
      if (Before.Line > After.Line) or ((Before.Line = After.Line) and (Before.Character > After.Character)) then
        Exit(Fail(Format('Die Änderungen in %s überschneiden sich', [ExtractFileName(AFile.FileName)])));
    end;
    AFile.Edits := AFile.Edits + [Edits[Index]];
  end;
  Result := True;
end;

function TGenericListConversion.Finish(out APlan: TGenericListPlan): Boolean;
var
  Cast: TCastUse;
  Distinct: TArray<string>;
  Index: Integer;
  SourceFile: TSourceFile;
  FileEdits: TFileTextEdits;
  Known: Boolean;
  Token: TPascalToken;
begin
  APlan := Default(TGenericListPlan);
  if Failed then
    Exit(False);
  if FCasts = nil then
    Exit(Fail(Format('%s wird nirgends mit Cast gelesen; der Elementtyp ist unbekannt', [FName])));
  Distinct := nil;
  for Cast in FCasts do
    if not MatchText(LastName(Cast.TypeText), Distinct) then
      Distinct := Distinct + [LastName(Cast.TypeText)];
  if Length(Distinct) > 1 then
    Exit(Fail(Format('%s wird mit verschiedenen Casts gelesen: %s', [FName, string.Join(', ', Distinct)])));
  if MatchText(LastName(ItemType), ScalarTypes) then
    Exit(Fail(Format('%s enthält Werte vom Typ %s statt Objekte', [FName, LastName(ItemType)])));
  CheckElements;
  if Failed then
    Exit(False);
  if (FKind.CreateArguments <> '') and not FCreated then
    Exit(Fail(Format('%s wird hier nicht erzeugt; ohne Create lässt sich nicht festlegen, dass %s<T> die Objekte ' +
      'nicht besitzt', [FName, FKind.GenericName])));
  for Index := 1 to FFiles.Count - 1 do
  begin
    SourceFile := FFiles[Index];
    if SourceFile.GenericAt = nil then
      Continue;
    // Der neue Typtext nennt T: dort muss T bekannt sein.
    Known := False;
    for Token in SourceFile.Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, LastName(ItemType)) then
        Known := True;
    if not Known then
      Exit(Fail(Format('%s ist in %s nicht bekannt', [ItemType, ExtractFileName(SourceFile.FileName)])));
  end;
  for Index := 0 to FFiles.Count - 1 do
  begin
    SourceFile := FFiles[Index];
    if (SourceFile.GenericAt <> nil) or (SourceFile.Rewritten <> nil) then
      AddUsesEdits(SourceFile);
    if Failed or not Finalize(SourceFile) then
      Exit(False);
  end;
  APlan.Title := Format('In %s umwandeln', [GenericText]);
  APlan.ItemType := ItemType;
  APlan.Edits := FFiles[0].Edits;
  for Index := 1 to FFiles.Count - 1 do
    if FFiles[Index].Edits <> nil then
    begin
      FileEdits.FileName := FFiles[Index].FileName;
      FileEdits.Edits := FFiles[Index].Edits;
      APlan.FileEdits := APlan.FileEdits + [FileEdits];
    end;
  APlan.Safe := not FUnknown and (APlan.FileEdits = nil);
  Result := True;
end;

end.
