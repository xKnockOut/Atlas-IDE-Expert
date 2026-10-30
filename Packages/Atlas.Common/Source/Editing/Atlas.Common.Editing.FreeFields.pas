unit Atlas.Common.Editing.FreeFields;

// Felder im Destruktor freigeben (#666): Atlas sucht Objektfelder, die der
// Konstruktor erzeugt, die die Klasse aber nirgends freigibt.
//   - Erzeugt: Zuweisung FFeld := TKlasse.Create(…) (auch Self.FFeld, auch
//     CreateFmt, CreateNew und generische Klassen) im Konstruktor oder in einer
//     privaten Methode der Klasse, die er (auch über weitere private Methoden)
//     aufruft. Die Reihenfolge der ersten Erzeugung zählt.
//   - Freigegeben: FFeld.Free, FFeld.Destroy, FFeld.DisposeOf oder
//     FreeAndNil(FFeld) in irgendeiner Methode der Klasse.
//   - Ausgenommen: Felder vom Interface-, Record- oder anderem Nicht-Klassentyp,
//     Records mit Create (TStopwatch.Create), Komponenten mit einem Owner
//     ungleich nil (TComponent-Nachfahren laut Datei, Index und einer Liste
//     häufiger VCL-Komponenten; Typen mit unbekannten Vorfahren mit Self,
//     AOwner, Owner, Application oder einem Komponentenfeld der Klasse als
//     erstem Argument) und Objekte, die die Klasse einem
//     Interface-Feld zuweist (FLog := FLogImpl): die Referenzzählung gibt sie
//     frei (#918). TObjectList und TObjectDictionary sind normale Felder.
//   - Unklar (Meldung ohne Aktion): Das Feld wird zurückgegeben (Result :=
//     FFeld, Exit(FFeld)), an eine Property eines anderen Objekts oder an
//     dessen Add…, Insert…, Register…, Attach…, Push oder Enqueue übergeben,
//     auch ohne Create zugewiesen oder über "write FFeld" von außen gesetzt.
//   - Übernommen (still): Add… usw. an ein Objekt, das seine Elemente
//     besitzt: ein Feld vom Typ TObjectList, TObjectStack, TObjectQueue oder
//     TComponentList (nicht mit False erzeugt) oder ein Feld einer Klasse, die
//     eine solche Liste für den Elementtyp als Feld hat (Datei oder Index; ihr
//     OwnsObjects sieht Atlas nicht, es gilt der Standard True).
//   - TArray<T> ist ein dynamisches Array, auch wenn der Index nur die Klasse
//     TArray aus System.Generics.Collections kennt.
//   - Freigabe: vor dem ersten inherited im Destruktor, sonst vor dessen
//     "end", in umgekehrter Erzeugungsreihenfolge, als FFeld.Free oder
//     FreeAndNil(FFeld). Fehlt der Destruktor, kommt "destructor Destroy;
//     override;" in den public-Abschnitt (hinter den Konstruktor, sonst ans
//     Ende des letzten public-Abschnitts, sonst in einen neuen) und der Rumpf
//     mit inherited hinter den letzten Konstruktor.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions;

type
  {$SCOPEDENUMS ON}
  /// <summary>Form der Freigabe: FFeld.Free oder FreeAndNil(FFeld).</summary>
  TFreeFieldsStyle = (Free, FreeAndNil);
  /// <summary>Nicht freigegeben (Aktion) oder unklar, ob die Klasse das Objekt besitzt (nur Meldung).</summary>
  TOwnedFieldState = (NotFreed, Unclear);
  {$SCOPEDENUMS OFF}

  TOwnedField = record
    ClassName: string;
    /// <summary>Zeile der Kopfzeile der Klasse.</summary>
    ClassLine: Integer;
    Name: string;
    /// <summary>Typ der Felddeklaration, z. B. TObjectList&lt;TOrder&gt;.</summary>
    TypeName: string;
    /// <summary>Name in der Felddeklaration.</summary>
    Range: TTextRange;
    /// <summary>Methode der ersten Erzeugung, z. B. TOrderList.Create.</summary>
    CreatedIn: string;
    /// <summary>Erzeugte Klasse, z. B. TStringList.</summary>
    CreatedType: string;
    /// <summary>Stelle der ersten Erzeugung in der Klasse, ab 0.</summary>
    Order: Integer;
    State: TOwnedFieldState;
    /// <summary>Bei Unclear: warum, z. B. "wird von TFoo.Take zurückgegeben".</summary>
    Reason: string;
  end;

  TFreeFields = class
  public const
    FieldTitle = 'Im Destruktor freigeben';
    ClassTitle = 'Alle eigenen Objekte freigeben (%d)';
  public
    /// <summary>Stil aus dem Wert der Einstellung: freeAndNil, sonst Free.</summary>
    class function StyleOf(const AName: string): TFreeFieldsStyle; static;
    /// <summary>Im Konstruktor erzeugte und nicht freigegebene Felder aller Klassen in ATree; AIndex (auch nil)
    /// klärt Typen und Vorfahren aus anderen Units.</summary>
    class function Analyze(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex):
      TArray<TOwnedField>; static;
    /// <summary>"FFeld.Free;" bzw. "FreeAndNil(FFeld);".</summary>
    class function Statement(const AField: string; AStyle: TFreeFieldsStyle): string; static;
    /// <summary>Freigabe von AFields (alle aus derselben Klasse) im Destruktor; legt ihn an, wenn er fehlt.
    /// False, wenn die Klasse nicht passt oder AFields leer ist.</summary>
    class function Edits(ATree: TSyntaxTree; const AText: string; const AFields: TArray<TOwnedField>;
      AStyle: TFreeFieldsStyle; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>AStatements in den Destruktor der Klasse AClassName (Kopfzeile ALine): vor das erste inherited,
    /// sonst vor "end"; fehlt er, wird er hinter dem letzten Konstruktor angelegt (#944). False ohne Klasse oder
    /// ohne Destruktor und Konstruktor.</summary>
    class function DestructorEdits(ATree: TSyntaxTree; const AText, AClassName: string; ALine: Integer;
      const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Auf der Deklaration eines nicht freigegebenen Felds „Im Destruktor freigeben“ (nur mit
    /// AWithFieldAction) und, ab zwei Feldern, die Aktion für die ganze Klasse; auf der Kopfzeile der Klasse
    /// „Alle eigenen Objekte freigeben (n)“.</summary>
    class function Actions(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex; ALine: Integer;
      AStyle: TFreeFieldsStyle; AWithFieldAction: Boolean): TArray<TCodeAction>; static;
    /// <summary>Erzeugt AValue ein Objekt, das jemand freigeben muss (TKlasse.Create…, keine Records, Interfaces
    /// usw.)? AOwned: eine Komponente mit Owner ungleich nil, die ihr Owner freigibt (#971).</summary>
    class function ObjectCreation(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean; static;
    /// <summary>Ist ATypeName eine Klasse oder unbekannt, also kein Record, Interface oder anderer Typ (#971)?
    /// </summary>
    class function IsObjectType(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
      const ATypeName: string): Boolean; static;
    /// <summary>AStatements in den class destructor der Klasse AClassDecl, vor dessen "end"; fehlt er, wird er
    /// hinter dem class constructor deklariert und angelegt (#971). False ohne class constructor bzw. wenn
    /// kein Platz zu finden ist.</summary>
    class function ClassDestructorEdits(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
      const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Text.Lines;

const
  FreeMethods: array[0..2] of string = ('Free', 'Destroy', 'DisposeOf');
  OwnerNames: array[0..3] of string = ('Self', 'AOwner', 'Owner', 'Application');
  // Records der RTL mit Create; ohne Index sähen sie wie Klassen aus.
  KnownRecords: array[0..14] of string = ('TStopwatch', 'TTimeSpan', 'TRect', 'TRectF', 'TPoint', 'TPointF',
    'TSize', 'TSizeF', 'TGUID', 'TFormatSettings', 'TValue', 'TEncodingHelper', 'TRegEx', 'TMatch', 'TRttiContext');
  /// <summary>Häufige VCL-Komponenten ohne einen der ComponentRoots im Namen (#918).</summary>
  KnownComponents: array[0..21] of string = ('TMenuItem', 'TMenu', 'TPopupMenu', 'TMainMenu', 'TTimer',
    'TActionList', 'TAction', 'TBasicAction', 'TImageList', 'TCustomImageList', 'TCommonDialog', 'TOpenDialog',
    'TSaveDialog', 'TApplicationEvents', 'TComboBox', 'TEdit', 'TButton', 'TLabel', 'TListBox', 'TMemo',
    'TCheckBox', 'TScrollBox');
  /// <summary>Häufige Klassen, die sicher keine Komponenten sind.</summary>
  KnownNonComponents: array[0..9] of string = ('TObject', 'TInterfacedObject', 'TPersistent', 'TThread',
    'TStream', 'TStrings', 'TStringList', 'TList', 'TObjectList', 'TDictionary');
  /// <summary>Grund für Felder, die ein Interface-Feld übernimmt; sie werden nie gemeldet.</summary>
  InterfaceReason = 'interface';
  /// <summary>Grund für Komponenten mit Owner und Objekte, die eine besitzende Liste übernimmt.</summary>
  OwnedReason = 'owned';
  /// <summary>Listen, die ihre Elemente standardmäßig freigeben (OwnsObjects = True).</summary>
  OwningContainers: array[0..3] of string = ('TObjectList', 'TObjectStack', 'TObjectQueue', 'TComponentList');

type
  TTypeGuess = (tgUnknown, tgClass, tgRecord, tgInterface, tgOther);

  /// <summary>Offener Knoten beim Suchen nach Create: Knoten und Methode, in der er steht.</summary>
  TCreationEntry = record
    Node: TSyntaxNode;
    Method: string;
  end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Leerraum zu je einem Leerzeichen zusammenfassen.</summary>
function Collapse(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space and (Result <> '') then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
    end;
end;

/// <summary>Methoden, die ein übergebenes Objekt übernehmen können: Add, Insert, Push, Enqueue, Register,
/// Attach und ihre Varianten (AddObject, RegisterListener).</summary>
function HandsOver(const AMethod: string): Boolean;
begin
  Result := StartsText('Add', AMethod) or StartsText('Insert', AMethod) or SameText(AMethod, 'Push') or
    SameText(AMethod, 'Enqueue') or StartsText('Register', AMethod) or StartsText('Attach', AMethod);
end;

/// <summary>Name ohne generische Argumente: TObjectList&lt;TOrder&gt; → TObjectList.</summary>
function BaseName(const ATypeName: string): string;
var
  Angle: Integer;
begin
  Result := Trim(ATypeName);
  Angle := Pos('<', Result);
  if Angle > 0 then
    Result := Trim(Copy(Result, 1, Angle - 1));
end;

/// <summary>Erzeugung mit dem Argument False, z. B. TObjectList&lt;TFoo&gt;.Create(False).</summary>
function CreatedWithFalse(AValue: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (AValue = nil) or (AValue.Kind <> TSyntaxKind.Call) then
    Exit;
  for Index := 1 to AValue.ChildCount - 1 do
    if (AValue[Index].Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
      SameText(AValue[Index].Name, 'False') then
      Exit(True);
end;

{ TClassAnalyzer }

type
  TClassAnalyzer = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FIndex: ISymbolIndex;
    FDecl: TSyntaxNode;
    FClassNode: TSyntaxNode;
    FClassName: string;
    FFields: TArray<TOwnedField>;
    FInterfaceFields: TArray<string>;
    FPrivate: TArray<string>;
    FMethods: TArray<TSyntaxNode>;
    FVisited: TArray<string>;
    FCreated: TArray<Integer>;
    /// <summary>Felder, die mit dem Argument False erzeugt werden (TObjectList.Create(False)).</summary>
    FNotOwning: TArray<Integer>;
    FCurrent: string;
    function FieldIndex(const AName: string): Integer;
    function FieldRef(ANode: TSyntaxNode): Integer;
    /// <summary>ANode ist FFeld oder Self.FFeld mit einem Interface-Typ.</summary>
    function IsInterfaceField(ANode: TSyntaxNode): Boolean;
    function MethodBody(const AName: string): TSyntaxNode;
    function TypeGuess(const ATypeName: string): TTypeGuess;
    function ComponentChain(const ATypeName: string; out AEndsKnown: Boolean): TArray<string>;
    function IsComponent(const ATypeName: string): Boolean;
    /// <summary>True, wenn die Vorfahrenkette von ATypeName sicher endet: bei einer Komponente, bei
    /// einer Klasse ohne Vorfahren oder bei einer bekannten Nicht-Komponente (#918).</summary>
    function ComponentKnown(const ATypeName: string): Boolean;
    function Creation(AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
    function IsCreation(AValue: TSyntaxNode): Boolean;
    function CalledPrivate(AStatement: TSyntaxNode): string;
    /// <summary>Typen der Felder der Klasse AClassName aus Datei oder Index, samt Typargumenten.</summary>
    function ClassFieldTypes(const AClassName: string): TArray<string>;
    /// <summary>Übernimmt AReceiver.Add…(Feld AField) das Objekt? Ja, wenn AReceiver ein Feld ist, das selbst
    /// eine besitzende Liste für den Typ von AField ist oder eine solche als Feld hat.</summary>
    function TakesOver(AReceiver: TSyntaxNode; AField: Integer): Boolean;
    procedure ScanCreations(ANode: TSyntaxNode);
    procedure ScanUses(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
    procedure CheckUse(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
    procedure SetUnclear(AField: Integer; const AReason: string);
    procedure ReadClass;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex; ADecl: TSyntaxNode);
    function Fields: TArray<TOwnedField>;
  end;

/// <summary>Routinen der Datei: implementation-Abschnitt bzw. Programmdatei.</summary>
function RoutineDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Section := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Section := ATree.Root;
  for Index := 0 to Section.ChildCount - 1 do
    if Section[Index].Kind = TSyntaxKind.RoutineDecl then
      Result := Result + [Section[Index]];
end;

/// <summary>Methoden TKlasse.Name mit Rumpf, ohne Methoden verschachtelter Klassen.</summary>
function ClassMethods(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>;
var
  Decl: TSyntaxNode;
  Rest: string;
begin
  Result := nil;
  for Decl in RoutineDecls(ATree) do
    if StartsText(AClassName + '.', Decl.Name) and (Decl.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Rest := Copy(Decl.Name, Length(AClassName) + 2, MaxInt);
      if (Rest <> '') and (Pos('.', Rest) = 0) then
        Result := Result + [Decl];
    end;
end;

function HeaderOf(ADecl: TSyntaxNode): TSyntaxNode;
begin
  Result := ADecl.FindChild(TSyntaxKind.RoutineHeader);
end;

function StartsWithWord(const AText, AWord: string): Boolean;
var
  Text: string;
begin
  Text := TrimLeft(AText);
  Result := StartsText(AWord, Text) and ((Length(Text) = Length(AWord)) or
    not CharInSet(Text[Length(AWord) + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

function IsConstructorDecl(const AText: string; ADecl: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
begin
  Header := HeaderOf(ADecl);
  Result := (Header <> nil) and StartsWithWord(NodeText(AText, Header), 'constructor');
end;

function IsDestructorHeader(const AText: string; AHeader: TSyntaxNode): Boolean;
begin
  Result := (AHeader <> nil) and SameText(AHeader.Name, 'Destroy') and
    StartsWithWord(NodeText(AText, AHeader), 'destructor');
end;

constructor TClassAnalyzer.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  ADecl: TSyntaxNode);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FIndex := AIndex;
  FDecl := ADecl;
  // Ohne Klasse (ADecl = nil) nur für Typen und Erzeugungen außerhalb von Klassen (#971).
  if ADecl = nil then
    Exit;
  FClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  FClassName := ADecl.Name;
end;

function TClassAnalyzer.FieldIndex(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FFields) do
    if SameText(FFields[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

function TClassAnalyzer.FieldRef(ANode: TSyntaxNode): Integer;
begin
  Result := -1;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := FieldIndex(ANode.Name)
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := FieldIndex(ANode.Name);
end;

function TClassAnalyzer.IsInterfaceField(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := MatchText(ANode.Name, FInterfaceFields)
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := MatchText(ANode.Name, FInterfaceFields);
end;

function TClassAnalyzer.MethodBody(const AName: string): TSyntaxNode;
var
  Decl: TSyntaxNode;
begin
  for Decl in FMethods do
    if SameText(Decl.Name, FClassName + '.' + AName) then
      Exit(Decl);
  Result := nil;
end;

function TClassAnalyzer.TypeGuess(const ATypeName: string): TTypeGuess;
var
  Base: string;
  Location: TSymbolLocation;
  Depth: Integer;
  Found: Boolean;

  function FromFile(const AName: string; out AAlias: string): TTypeGuess;
  var
    Guess: TTypeGuess;
    Found: string;
  begin
    // out-Parameter lassen sich nicht in der anonymen Methode verwenden.
    Guess := tgUnknown;
    Found := '';
    FTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Index: Integer;
      begin
        Result := Guess = tgUnknown;
        if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, AName) then
          Exit;
        for Index := 0 to ANode.ChildCount - 1 do
          case ANode[Index].Kind of
            TSyntaxKind.ClassType:
              Guess := tgClass;
            TSyntaxKind.RecordType:
              Guess := tgRecord;
            TSyntaxKind.InterfaceType:
              Guess := tgInterface;
            TSyntaxKind.ObjectType, TSyntaxKind.ClassOfType, TSyntaxKind.EnumType, TSyntaxKind.SetType,
            TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
            TSyntaxKind.HelperType:
              Guess := tgOther;
            TSyntaxKind.TypeReference:
              if Found = '' then
                Found := ANode[Index].Name;
          end;
      end);
    AAlias := Found;
    Result := Guess;
  end;

var
  Alias: string;
  Generic: Boolean;
begin
  Base := BaseName(ATypeName);
  Result := tgUnknown;
  // TArray<T> ist ein dynamisches Array aus System; die Klasse TArray (System.Generics.Collections) trägt
  // keine Typparameter.
  Generic := Pos('<', ATypeName) > 0;
  if Generic and SameText(Base, 'TArray') then
    Exit(tgOther);
  for Depth := 1 to 8 do
  begin
    if Base = '' then
      Exit;
    Result := FromFile(Base, Alias);
    if Result <> tgUnknown then
      Exit;
    Found := False;
    if (Alias = '') and (FIndex <> nil) then
      for Location in FIndex.FindSymbols(Base) do
        // Mit Typargumenten zählen nur generische Typen gleichen Namens.
        if (Location.Symbol.Container = '') and not (Generic and (Location.Symbol.TypeParams = '')) then
        begin
          case Location.Symbol.Kind of
            TIndexSymbolKind.ClassType:
              Result := tgClass;
            TIndexSymbolKind.RecordType:
              Result := tgRecord;
            TIndexSymbolKind.InterfaceType:
              Result := tgInterface;
            TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType:
              Result := tgOther;
          else
            Continue;
          end;
          Found := True;
          Break;
        end;
    if Found then
      Exit;
    // Alias in der Datei (TFoo = TBar): weiter mit TBar.
    if Alias = '' then
      Break;
    Base := BaseName(Alias);
    Generic := Pos('<', Alias) > 0;
  end;
  if MatchText(Base, KnownRecords) then
    Result := tgRecord
  else if TRegEx.IsMatch(Base, '^I[A-Z]') then
    Result := tgInterface;
end;

function TClassAnalyzer.ComponentChain(const ATypeName: string; out AEndsKnown: Boolean): TArray<string>;
var
  Name, Next: string;
  Location: TSymbolLocation;
  Depth: Integer;
  Declared: Boolean;
begin
  Name := BaseName(ATypeName);
  Result := [Name];
  AEndsKnown := False;
  for Depth := 1 to 32 do
  begin
    Next := '';
    Declared := False;
    FTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Kind: TSyntaxNode;
      begin
        Result := not Declared;
        if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, Name) then
        begin
          Kind := ANode.FindChild(TSyntaxKind.ClassType);
          if Kind = nil then
            Exit;
          Declared := True;
          if (Kind.ChildCount > 0) and (Kind[0].Kind = TSyntaxKind.TypeReference) then
            Next := Kind[0].Name;
        end;
      end);
    if not Declared and (FIndex <> nil) then
      for Location in FIndex.FindSymbols(Name) do
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
        begin
          Declared := True;
          if Length(Location.Symbol.Ancestors) > 0 then
            Next := BaseName(Location.Symbol.Ancestors[0]);
          Break;
        end;
    // Klasse ohne Vorfahren stammt von TObject ab: das Ende ist bekannt.
    if Declared and (Next = '') then
      AEndsKnown := True;
    if (Next = '') or (IndexText(Next, Result) >= 0) then
      Break;
    Result := Result + [Next];
    Name := Next;
  end;
  if DescendsFrom(Result, ComponentRoots) or DescendsFrom(Result, KnownComponents) or
    DescendsFrom(Result, KnownNonComponents) then
    AEndsKnown := True;
end;

function TClassAnalyzer.IsComponent(const ATypeName: string): Boolean;
var
  Chain: TArray<string>;
  EndsKnown: Boolean;
begin
  Chain := ComponentChain(ATypeName, EndsKnown);
  Result := DescendsFrom(Chain, ComponentRoots) or DescendsFrom(Chain, KnownComponents);
end;

function TClassAnalyzer.ComponentKnown(const ATypeName: string): Boolean;
begin
  ComponentChain(ATypeName, Result);
end;

function TClassAnalyzer.Creation(AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
var
  Access, Receiver, Argument: TSyntaxNode;
  Name: string;
begin
  Result := False;
  ATypeName := '';
  AOwned := False;
  if AValue = nil then
    Exit;
  Argument := nil;
  if (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount >= 1) and
    (AValue[0].Kind = TSyntaxKind.MemberAccess) then
  begin
    Access := AValue[0];
    if AValue.ChildCount >= 2 then
      Argument := AValue[1];
  end
  else if AValue.Kind = TSyntaxKind.MemberAccess then
    Access := AValue
  else
    Exit;
  if not StartsText('Create', Access.Name) or (Access.ChildCount < 1) then
    Exit;
  Receiver := Access[0];
  if Receiver.Kind = TSyntaxKind.Identifier then
  begin
    if SameText(Receiver.Name, 'Self') or (FieldIndex(Receiver.Name) >= 0) then
      Exit;
    ATypeName := Receiver.Name;
  end
  else if (Receiver.Kind = TSyntaxKind.MemberAccess) and (Receiver.ChildCount >= 2) and
    (Receiver[0].Kind = TSyntaxKind.Identifier) and (Receiver[1].Kind = TSyntaxKind.GenericArgs) then
    ATypeName := Collapse(NodeText(FText, Receiver))
  else
    Exit;
  if TypeGuess(ATypeName) in [tgRecord, tgInterface, tgOther] then
    Exit;
  Result := True;
  // Owner ungleich nil: die Komponente gibt ihr Owner frei.
  if (Argument = nil) or ((Argument.Kind = TSyntaxKind.Literal) and SameText(Argument.Name, 'nil')) then
    Exit;
  if IsComponent(ATypeName) then
    AOwned := True
  else if not ComponentKnown(ATypeName) then
  begin
    // Unbekannte Vorfahren (z. B. VCL-Klassen ohne Index): Owner am Argument erkennen.
    Name := '';
    if Argument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      Name := Argument.Name;
    AOwned := MatchText(Name, OwnerNames);
  end;
  // Owner ist ein Komponentenfeld der Klasse (Host := TForm.Create…; Box := TFoo.Create(Host)).
  if not AOwned and (FieldRef(Argument) >= 0) and IsComponent(FFields[FieldRef(Argument)].TypeName) then
    AOwned := True;
end;

function TClassAnalyzer.IsCreation(AValue: TSyntaxNode): Boolean;
var
  TypeName: string;
  Owned: Boolean;
begin
  Result := Creation(AValue, TypeName, Owned);
end;

function TClassAnalyzer.CalledPrivate(AStatement: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount < 1) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount >= 1) then
    Target := Target[0];
  if Target.Kind = TSyntaxKind.Identifier then
    Result := Target.Name
  else if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
    (Target[0].Kind = TSyntaxKind.Identifier) and SameText(Target[0].Name, 'Self') then
    Result := Target.Name;
  if IndexText(Result, FPrivate) < 0 then
    Result := '';
end;

function TClassAnalyzer.ClassFieldTypes(const AClassName: string): TArray<string>;
var
  Found: TArray<string>;
  Declared: Boolean;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  TypeName: string;
begin
  // out- und Result-Werte lassen sich nicht in der anonymen Methode füllen.
  Found := nil;
  Declared := False;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      ClassNode, TypeRef: TSyntaxNode;
      Index: Integer;
    begin
      Result := not Declared;
      if not Result or (ANode.Kind <> TSyntaxKind.TypeDecl) or not SameText(ANode.Name, AClassName) then
        Exit;
      ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if ClassNode = nil then
        Exit;
      Declared := True;
      for Index := 0 to ClassNode.ChildCount - 1 do
        if ClassNode[Index].Kind = TSyntaxKind.Field then
        begin
          TypeRef := ClassNode[Index].FindChild(TSyntaxKind.TypeReference);
          if TypeRef <> nil then
            Found := Found + [Collapse(NodeText(FText, TypeRef))];
        end;
    end);
  if not Declared and (FIndex <> nil) then
    for Location in FIndex.FindSymbols(AClassName) do
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
        FIndex.FindUnit(Location.UnitName, UnitIndex) then
      begin
        for Symbol in UnitIndex.Symbols do
          if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AClassName) then
          begin
            TypeName := BaseName(Symbol.TypeName);
            if Symbol.TypeArgs <> '' then
              TypeName := TypeName + '<' + Symbol.TypeArgs + '>';
            Found := Found + [TypeName];
          end;
        Break;
      end;
  Result := Found;
end;

function TClassAnalyzer.TakesOver(AReceiver: TSyntaxNode; AField: Integer): Boolean;
var
  Receiver, Index: Integer;
  Elements: TArray<string>;
  EndsKnown: Boolean;
  FieldType: string;

  // Besitzende Liste, deren Elementtyp AField aufnimmt (ohne Typargument: jedes Objekt).
  function Owns(const AContainer: string): Boolean;
  var
    Args: string;
  begin
    Result := MatchText(BaseName(AContainer), OwningContainers);
    if not Result or (Pos('<', AContainer) = 0) then
      Exit;
    Args := Copy(AContainer, Pos('<', AContainer) + 1, MaxInt);
    if EndsText('>', Args) then
      Args := Copy(Args, 1, Length(Args) - 1);
    Result := MatchText(BaseName(Args), Elements);
  end;

begin
  Result := False;
  Receiver := FieldRef(AReceiver);
  if (Receiver < 0) or (AField < 0) then
    Exit;
  FieldType := FFields[AField].CreatedType;
  if FieldType = '' then
    FieldType := FFields[AField].TypeName;
  Elements := ComponentChain(FieldType, EndsKnown) + [BaseName(FFields[AField].TypeName), 'TObject'];
  if Owns(FFields[Receiver].TypeName) then
  begin
    // TObjectList.Create(False) besitzt nichts.
    for Index in FNotOwning do
      if Index = Receiver then
        Exit(False);
    Exit(True);
  end;
  for FieldType in ClassFieldTypes(BaseName(FFields[Receiver].TypeName)) do
    if Owns(FieldType) then
      Exit(True);
end;

procedure TClassAnalyzer.ScanCreations(ANode: TSyntaxNode);
var
  Pending: TStack<TCreationEntry>;
  Entry, Next: TCreationEntry;
  Node, Body: TSyntaxNode;
  Index, Field: Integer;
  TypeName, Called, Saved: string;
  Owned: Boolean;
begin
  // Eigener Stapel statt Rekursion: Lange Ausdrucksketten dürfen den Aufrufstapel nicht
  // erschöpfen. Die Reihenfolge bleibt die der Rekursion: Knoten, dann der Rumpf einer
  // aufgerufenen privaten Methode, dann die Kinder von links nach rechts.
  Saved := FCurrent;
  Pending := TStack<TCreationEntry>.Create;
  try
    Entry.Node := ANode;
    Entry.Method := FCurrent;
    Pending.Push(Entry);
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      Node := Entry.Node;
      if (Node = nil) or (Node.Kind = TSyntaxKind.AnonymousMethod) then
        Continue;
      FCurrent := Entry.Method;
      if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount >= 2) then
      begin
        Field := FieldRef(Node[0]);
        if (Field >= 0) and (FFields[Field].CreatedIn = '') and Creation(Node[1], TypeName, Owned) then
        begin
          FFields[Field].CreatedIn := FCurrent;
          FFields[Field].CreatedType := TypeName;
          FFields[Field].Order := Length(FCreated);
          FCreated := FCreated + [Field];
          // Komponenten mit Owner gelten als erzeugt, aber nicht als eigen.
          if Owned then
            FFields[Field].Reason := OwnedReason;
          if CreatedWithFalse(Node[1]) then
            FNotOwning := FNotOwning + [Field];
        end;
      end;
      Next.Method := Entry.Method;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Next.Node := Node[Index];
        Pending.Push(Next);
      end;
      // Zuletzt abgelegt, also vor den Kindern durchsucht.
      Called := CalledPrivate(Node);
      if (Called <> '') and (IndexText(Called, FVisited) < 0) then
      begin
        FVisited := FVisited + [Called];
        Body := MethodBody(Called);
        if Body <> nil then
        begin
          Next.Node := Body.FindChild(TSyntaxKind.Block);
          Next.Method := Body.Name;
          Pending.Push(Next);
        end;
      end;
    end;
  finally
    Pending.Free;
    FCurrent := Saved;
  end;
end;

procedure TClassAnalyzer.SetUnclear(AField: Integer; const AReason: string);
begin
  // Komponenten mit Owner und vom Interface übernommene Objekte gibt ein anderer frei,
  // gleich wohin sie die Klasse weiterreicht.
  if (AField >= 0) and (FFields[AField].State <> TOwnedFieldState.Unclear) and
    (FFields[AField].Reason <> InterfaceReason) and (FFields[AField].Reason <> OwnedReason) then
  begin
    FFields[AField].State := TOwnedFieldState.Unclear;
    FFields[AField].Reason := AReason;
  end;
end;

procedure TClassAnalyzer.ScanUses(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Eigener Stapel statt Rekursion, damit tiefe Ausdrücke den Aufrufstapel nicht erschöpfen.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if Node = nil then
        Continue;
      CheckUse(Node, AMethod, AFreed);
      for Index := Node.ChildCount - 1 downto 0 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

procedure TClassAnalyzer.CheckUse(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
var
  Field: Integer;
  Index: Integer;
  Target: TSyntaxNode;
begin
  case ANode.Kind of
    TSyntaxKind.MemberAccess:
      if (ANode.ChildCount >= 1) and MatchText(ANode.Name, FreeMethods) then
      begin
        Field := FieldRef(ANode[0]);
        if Field >= 0 then
          AFreed[Field] := True;
      end;
    TSyntaxKind.Call:
      if (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) then
      begin
        Field := FieldRef(ANode[1]);
        if SameText(ANode[0].Name, 'FreeAndNil') and (Field >= 0) then
          AFreed[Field] := True
        else if SameText(ANode[0].Name, 'Exit') then
          SetUnclear(Field, Format('wird von %s zurückgegeben', [AMethod]));
      end
      else if (ANode.ChildCount >= 2) and (ANode[0].Kind = TSyntaxKind.MemberAccess) and
        (ANode[0].ChildCount = 1) and not ((ANode[0][0].Kind = TSyntaxKind.Identifier) and
        SameText(ANode[0][0].Name, 'Self')) and HandsOver(ANode[0].Name) then
        // Liste.Add(FFeld), Dienst.Register(FFeld): das andere Objekt kann es übernehmen (#918). Besitzt es
        // seine Elemente (TObjectList oder eine Klasse mit einer), gibt es das Objekt frei.
        for Index := 1 to ANode.ChildCount - 1 do
          if TakesOver(ANode[0][0], FieldRef(ANode[Index])) then
          begin
            Field := FieldRef(ANode[Index]);
            FFields[Field].State := TOwnedFieldState.NotFreed;
            FFields[Field].Reason := OwnedReason;
          end
          else
            SetUnclear(FieldRef(ANode[Index]), Format('wird in %s an %s übergeben',
              [AMethod, Collapse(NodeText(FText, ANode[0]))]));
    TSyntaxKind.AssignStatement:
      if ANode.ChildCount >= 2 then
      begin
        Target := ANode[0];
        Field := FieldRef(ANode[1]);
        // Typumwandlung TKlasse(FFeld) zählt wie FFeld.
        if (Field < 0) and (ANode[1].Kind = TSyntaxKind.Call) and (ANode[1].ChildCount = 2) and
          (ANode[1][0].Kind = TSyntaxKind.Identifier) and IsInterfaceField(Target) then
          Field := FieldRef(ANode[1][1]);
        if (Field >= 0) and IsInterfaceField(Target) then
        begin
          // Das Interface-Feld übernimmt das Objekt; Free wäre eine doppelte Freigabe.
          FFields[Field].State := TOwnedFieldState.NotFreed;
          FFields[Field].Reason := InterfaceReason;
        end
        else if Field >= 0 then
        begin
          if (Target.Kind = TSyntaxKind.Identifier) and SameText(Target.Name, 'Result') then
            SetUnclear(Field, Format('wird von %s zurückgegeben', [AMethod]))
          else if (Target.Kind = TSyntaxKind.MemberAccess) and (FieldRef(Target) < 0) then
            SetUnclear(Field, Format('wird in %s an %s übergeben', [AMethod, Collapse(NodeText(FText, Target))]));
        end;
        Field := FieldRef(Target);
        if (Field >= 0) and not IsCreation(ANode[1]) and
          not ((ANode[1].Kind = TSyntaxKind.Literal) and SameText(ANode[1].Name, 'nil')) then
          SetUnclear(Field, Format('wird in %s auch ohne Create zugewiesen', [AMethod]));
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TClassAnalyzer.ReadClass;
var
  Index, Token: Integer;
  Child, TypeRef: TSyntaxNode;
  Name, Section, TypeName: string;
  Field: TOwnedField;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := FTree.Tokens;
  Section := 'public';
  for Index := 0 to FClassNode.ChildCount - 1 do
  begin
    Child := FClassNode[Index];
    case Child.Kind of
      TSyntaxKind.Visibility:
        Section := Child.Name;
      TSyntaxKind.RoutineHeader:
        if EndsText('private', Section) then
          FPrivate := FPrivate + [Child.Name];
      TSyntaxKind.Field:
        begin
          TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
          if TypeRef = nil then
            Continue;
          TypeName := Collapse(NodeText(FText, TypeRef));
          if TypeGuess(TypeName) = tgInterface then
            for Name in Child.Name.Split([',']) do
              FInterfaceFields := FInterfaceFields + [Trim(Name)];
          if TypeGuess(TypeName) in [tgRecord, tgInterface, tgOther] then
            Continue;
          for Name in Child.Name.Split([',']) do
          begin
            Field := Default(TOwnedField);
            Field.ClassName := FClassName;
            Field.ClassLine := FDecl.StartPos.Line;
            Field.Name := Trim(Name);
            Field.TypeName := TypeName;
            Field.Range := TTextRange.Create(Child.StartPos, Child.StartPos);
            for Token := TSyntaxTree.FirstTokenOf(Tokens, Child.StartOffset) to High(Tokens) do
              if (Tokens[Token].Offset >= Child.StartOffset) and (Tokens[Token].Offset < TypeRef.StartOffset) and
                (Tokens[Token].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Token].Text, Field.Name) then
              begin
                Field.Range := TTextRange.Create(Tokens[Token].StartPos, Tokens[Token].EndPos);
                Break;
              end;
            Field.Order := -1;
            FFields := FFields + [Field];
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TClassAnalyzer.Fields: TArray<TOwnedField>;
var
  Decl, Child: TSyntaxNode;
  Freed: TArray<Boolean>;
  Index: Integer;
  Match: TMatch;
begin
  Result := nil;
  if FClassNode = nil then
    Exit;
  ReadClass;
  if FFields = nil then
    Exit;
  FMethods := ClassMethods(FTree, FClassName);
  for Decl in FMethods do
    if IsConstructorDecl(FText, Decl) then
    begin
      FCurrent := Decl.Name;
      FVisited := nil;
      ScanCreations(Decl.FindChild(TSyntaxKind.Block));
    end;
  if FCreated = nil then
    Exit;
  SetLength(Freed, Length(FFields));
  for Decl in FMethods do
    ScanUses(Decl.FindChild(TSyntaxKind.Block), Decl.Name, Freed);
  // write FFeld: Das Objekt kann von außen kommen.
  for Index := 0 to FClassNode.ChildCount - 1 do
  begin
    Child := FClassNode[Index];
    if Child.Kind <> TSyntaxKind.PropertyDecl then
      Continue;
    Match := TRegEx.Match(NodeText(FText, Child), '\bwrite\s+(\w+)', [roIgnoreCase]);
    if Match.Success then
      SetUnclear(FieldIndex(Match.Groups[1].Value), Format('kann über die Property %s von außen gesetzt werden',
        [Child.Name]));
  end;
  for Index in FCreated do
    if not Freed[Index] and (FFields[Index].Reason <> OwnedReason) and (FFields[Index].Reason <> InterfaceReason) then
      Result := Result + [FFields[Index]];
end;

{ Destruktor }

type
  TDestructorPlace = record
    /// <summary>Deklaration in der Klasse; nil ohne.</summary>
    Declaration: TSyntaxNode;
    /// <summary>Rumpf TKlasse.Destroy; nil ohne.</summary>
    Body: TSyntaxNode;
    /// <summary>Letzter Konstruktor-Rumpf der Klasse; nil ohne.</summary>
    LastConstructor: TSyntaxNode;
  end;

function FindClassDecl(ATree: TSyntaxTree; const AClassName: string; ALine: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Found = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = ALine) and
        SameText(ANode.Name, AClassName) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
        Found := ANode;
    end);
  Result := Found;
end;

function PlaceOf(ATree: TSyntaxTree; const AText: string; ADecl: TSyntaxNode): TDestructorPlace;
var
  ClassNode, Header, Decl: TSyntaxNode;
  Index: Integer;
begin
  Result := Default(TDestructorPlace);
  ClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  for Index := 0 to ClassNode.ChildCount - 1 do
    if IsDestructorHeader(AText, ClassNode[Index]) and (ClassNode[Index].Kind = TSyntaxKind.RoutineHeader) then
      Result.Declaration := ClassNode[Index];
  for Decl in ClassMethods(ATree, ADecl.Name) do
  begin
    Header := HeaderOf(Decl);
    if SameText(Decl.Name, ADecl.Name + '.Destroy') and (Header <> nil) and
      StartsWithWord(NodeText(AText, Header), 'destructor') then
      Result.Body := Decl
    else if IsConstructorDecl(AText, Decl) then
      Result.LastConstructor := Decl;
  end;
end;

/// <summary>Klassenname des Rumpfs samt generischer Parameter: "constructor TFoo&lt;T&gt;.Create(…)" →
/// TFoo&lt;T&gt;.</summary>
function Qualifier(const AText: string; AConstructor: TSyntaxNode; const AClassName: string): string;
var
  Header: string;
  Stop: Integer;
begin
  // Text vom Anfang der Routine bis zum Block; der Kopfknoten generischer Klassen deckt nicht alles ab.
  Header := Collapse(Copy(AText, AConstructor.StartOffset + 1,
    AConstructor.FindChild(TSyntaxKind.Block).StartOffset - AConstructor.StartOffset));
  // "constructor" bzw. "class constructor" (#971) abschneiden.
  Header := Trim(Copy(Header, Pos('constructor', LowerCase(Header)) + Length('constructor'), MaxInt));
  Stop := Pos('(', Header);
  if Stop = 0 then
    Stop := Pos(';', Header);
  if Stop > 0 then
    Header := Copy(Header, 1, Stop - 1);
  Stop := LastDelimiter('.', Header);
  Result := AClassName;
  if Stop > 1 then
    Result := Trim(Copy(Header, 1, Stop - 1));
end;

function IsInheritedCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount >= 1) and
    (ANode[0].Kind = TSyntaxKind.InheritedExpr);
end;

function InsertAt(const APosition: TTextPosition; const AText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(APosition, APosition), AText);
end;

/// <summary>Freigaben in den vorhandenen Rumpf: vor das erste inherited, sonst vor "end".</summary>
function BodyEdit(const ALines: TArray<string>; ABody: TSyntaxNode; const AStatements: TArray<string>;
  const ALineBreak: string): TTextEdit;
var
  Block, Child, Anchor: TSyntaxNode;
  Index: Integer;
  Position: TTextPosition;
  Prefix, Indent, Text, Statement: string;
begin
  Block := ABody.FindChild(TSyntaxKind.Block);
  Anchor := nil;
  for Index := 0 to Block.ChildCount - 1 do
  begin
    Child := Block[Index];
    if IsInheritedCall(Child) then
    begin
      Anchor := Child;
      Break;
    end;
  end;
  if Anchor <> nil then
  begin
    Position := Anchor.StartPos;
    Indent := '';
  end
  else
  begin
    // "end" des Blocks: drei Zeichen vor dessen Ende.
    Position := TTextPosition.Create(Block.EndPos.Line, Block.EndPos.Character - 3);
    Indent := '  ';
  end;
  Prefix := '';
  if Position.Line <= High(ALines) then
    Prefix := Copy(ALines[Position.Line], 1, Position.Character);
  Text := '';
  if Trim(Prefix) = '' then
  begin
    // Eigene Zeilen vor der Ankerzeile, eingerückt wie sie (bzw. eine Stufe tiefer als "end").
    Indent := Prefix + Indent;
    for Statement in AStatements do
      Text := Text + Indent + Statement + ALineBreak;
    Result := InsertAt(TTextPosition.Create(Position.Line, 0), Text);
  end
  else
  begin
    for Statement in AStatements do
      Text := Text + Statement + ' ';
    Result := InsertAt(Position, Text);
  end;
end;

/// <summary>"destructor Destroy; override;" in den public-Abschnitt; False, wenn kein Platz zu finden ist.</summary>
function DeclarationEdit(const ALines: TArray<string>; const AText: string; ADecl: TSyntaxNode;
  const ALineBreak: string; out AEdit: TTextEdit): Boolean;
const
  Declaration = 'destructor Destroy; override;';
var
  ClassNode, Child, AfterConstructor, LastMember, PublicHead: TSyntaxNode;
  Index, Line: Integer;
  Section, Indent: string;
  InPublic: Boolean;
begin
  Result := False;
  ClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  AfterConstructor := nil;
  LastMember := nil;
  PublicHead := nil;
  InPublic := False;
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    if Child.Kind = TSyntaxKind.Visibility then
    begin
      Section := Child.Name;
      InPublic := SameText(Section, 'public');
      if InPublic then
      begin
        PublicHead := Child;
        LastMember := nil;
      end;
      Continue;
    end;
    if not InPublic or (Child.Kind = TSyntaxKind.TypeReference) then
      Continue;
    LastMember := Child;
    if (Child.Kind = TSyntaxKind.RoutineHeader) and StartsWithWord(NodeText(AText, Child), 'constructor') then
      AfterConstructor := Child;
  end;
  if AfterConstructor <> nil then
    LastMember := AfterConstructor;
  if LastMember <> nil then
  begin
    Line := LastMember.EndPos.Line;
    Indent := TTextLines.IndentOf(ALines[LastMember.StartPos.Line]);
    AEdit := InsertAt(TTextPosition.Create(Line, Length(ALines[Line])), ALineBreak + Indent + Declaration);
    Exit(True);
  end;
  if PublicHead <> nil then
  begin
    Line := PublicHead.EndPos.Line;
    Indent := TTextLines.IndentOf(ALines[PublicHead.StartPos.Line]) + '  ';
    AEdit := InsertAt(TTextPosition.Create(Line, Length(ALines[Line])), ALineBreak + Indent + Declaration);
    Exit(True);
  end;
  // Neuer Abschnitt vor dem "end" der Klasse, wenn es allein auf seiner Zeile steht.
  Line := ClassNode.EndPos.Line;
  if (Line > High(ALines)) or (Trim(Copy(ALines[Line], 1, ClassNode.EndPos.Character - 3)) <> '') then
    Exit;
  Indent := TTextLines.IndentOf(ALines[Line]);
  AEdit := InsertAt(TTextPosition.Create(Line, 0), Indent + 'public' + ALineBreak + Indent + '  ' + Declaration +
    ALineBreak);
  Result := True;
end;

{ TFreeFields }

class function TFreeFields.StyleOf(const AName: string): TFreeFieldsStyle;
begin
  if SameText(AName, 'freeAndNil') then
    Result := TFreeFieldsStyle.FreeAndNil
  else
    Result := TFreeFieldsStyle.Free;
end;

class function TFreeFields.Analyze(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex):
  TArray<TOwnedField>;
var
  Decls: TArray<TSyntaxNode>;
  Decl: TSyntaxNode;
  Analyzer: TClassAnalyzer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Decls := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // Klassen in Typabschnitten; verschachtelte Klassen nicht.
      Result := ANode.Kind <> TSyntaxKind.ClassType;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
        Decls := Decls + [ANode];
    end);
  for Decl in Decls do
  begin
    Analyzer := TClassAnalyzer.Create(ATree, AText, AIndex, Decl);
    try
      Result := Result + Analyzer.Fields;
    finally
      Analyzer.Free;
    end;
  end;
end;

class function TFreeFields.Statement(const AField: string; AStyle: TFreeFieldsStyle): string;
begin
  if AStyle = TFreeFieldsStyle.FreeAndNil then
    Result := Format('FreeAndNil(%s);', [AField])
  else
    Result := AField + '.Free;';
end;

class function TFreeFields.Edits(ATree: TSyntaxTree; const AText: string; const AFields: TArray<TOwnedField>;
  AStyle: TFreeFieldsStyle; out AEdits: TArray<TTextEdit>): Boolean;
var
  Statements: TArray<string>;
  Order: TArray<Integer>;
  Index, Other, Swap: Integer;
begin
  AEdits := nil;
  Result := False;
  if (ATree = nil) or (Length(AFields) = 0) then
    Exit;
  // Umgekehrte Erzeugungsreihenfolge.
  Order := nil;
  for Index := 0 to High(AFields) do
    Order := Order + [Index];
  for Index := 0 to High(Order) - 1 do
    for Other := Index + 1 to High(Order) do
      if AFields[Order[Other]].Order > AFields[Order[Index]].Order then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Other];
        Order[Other] := Swap;
      end;
  Statements := nil;
  for Index in Order do
    Statements := Statements + [Statement(AFields[Index].Name, AStyle)];
  Result := DestructorEdits(ATree, AText, AFields[0].ClassName, AFields[0].ClassLine, Statements, AEdits);
end;

class function TFreeFields.DestructorEdits(ATree: TSyntaxTree; const AText, AClassName: string; ALine: Integer;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  Decl: TSyntaxNode;
  Place: TDestructorPlace;
  Lines: TArray<string>;
  LineBreak, Body, Indent, Line: string;
  Edit: TTextEdit;
begin
  AEdits := nil;
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) or (Length(AStatements) = 0) then
    Exit;
  Decl := FindClassDecl(ATree, AClassName, ALine);
  if Decl = nil then
    Exit;
  Lines := TTextLines.SplitLines(AText, LineBreak);
  Place := PlaceOf(ATree, AText, Decl);
  if Place.Body <> nil then
  begin
    AEdits := [BodyEdit(Lines, Place.Body, AStatements, LineBreak)];
    Exit(True);
  end;
  if Place.LastConstructor = nil then
    Exit;
  if Place.Declaration = nil then
  begin
    if not DeclarationEdit(Lines, AText, Decl, LineBreak, Edit) then
      Exit;
    AEdits := [Edit];
  end;
  Indent := StringOfChar(' ', Place.LastConstructor.StartPos.Character);
  Body := Indent + Format('destructor %s.Destroy;', [Qualifier(AText, Place.LastConstructor, Decl.Name)]) +
    LineBreak + Indent + 'begin';
  for Line in AStatements do
    Body := Body + LineBreak + Indent + '  ' + Line;
  Body := Body + LineBreak + Indent + '  inherited;' + LineBreak + Indent + 'end;';
  AEdits := AEdits + [InsertAt(Place.LastConstructor.EndPos, LineBreak + LineBreak + Body)];
  Result := True;
end;

class function TFreeFields.Actions(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  ALine: Integer; AStyle: TFreeFieldsStyle; AWithFieldAction: Boolean): TArray<TCodeAction>;
var
  All, OfClass: TArray<TOwnedField>;
  Field, Hit: TOwnedField;
  OnField, OnClass: Boolean;
  Action: TCodeAction;
  Edits_: TArray<TTextEdit>;
begin
  Result := nil;
  All := Analyze(ATree, AText, AIndex);
  OnField := False;
  OnClass := False;
  Hit := Default(TOwnedField);
  for Field in All do
    if Field.State = TOwnedFieldState.NotFreed then
      if Field.Range.StartPos.Line = ALine then
      begin
        Hit := Field;
        OnField := True;
        Break;
      end
      else if Field.ClassLine = ALine then
      begin
        Hit := Field;
        OnClass := True;
      end;
  if not (OnField or OnClass) then
    Exit;
  OfClass := nil;
  for Field in All do
    if (Field.State = TOwnedFieldState.NotFreed) and (Field.ClassLine = Hit.ClassLine) and
      SameText(Field.ClassName, Hit.ClassName) then
      OfClass := OfClass + [Field];
  if OnField and AWithFieldAction and Edits(ATree, AText, [Hit], AStyle, Edits_) then
  begin
    Action := Default(TCodeAction);
    Action.Title := FieldTitle;
    Action.Kind := QuickFixKind;
    Action.Edits := Edits_;
    Action.IsPreferred := True;
    Result := Result + [Action];
  end;
  if (OnClass or (Length(OfClass) >= 2)) and Edits(ATree, AText, OfClass, AStyle, Edits_) then
  begin
    Action := Default(TCodeAction);
    Action.Title := Format(ClassTitle, [Length(OfClass)]);
    Action.Kind := QuickFixKind;
    Action.Edits := Edits_;
    Result := Result + [Action];
  end;
end;

class function TFreeFields.ObjectCreation(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
var
  Analyzer: TClassAnalyzer;
begin
  Analyzer := TClassAnalyzer.Create(ATree, AText, AIndex, nil);
  try
    Result := Analyzer.Creation(AValue, ATypeName, AOwned);
  finally
    Analyzer.Free;
  end;
end;

class function TFreeFields.IsObjectType(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  const ATypeName: string): Boolean;
var
  Analyzer: TClassAnalyzer;
begin
  Analyzer := TClassAnalyzer.Create(ATree, AText, AIndex, nil);
  try
    Result := not (Analyzer.TypeGuess(ATypeName) in [tgRecord, tgInterface, tgOther]);
  finally
    Analyzer.Free;
  end;
end;

/// <summary>Beginnt der Kopf mit "class constructor" bzw. "class destructor" (AKind)?</summary>
function IsClassStructor(const AText: string; AHeader: TSyntaxNode; const AKind: string): Boolean;
var
  Text: string;
begin
  Result := False;
  if AHeader = nil then
    Exit;
  Text := Collapse(NodeText(AText, AHeader));
  Result := StartsWithWord(Text, 'class') and StartsWithWord(Trim(Copy(Text, Length('class') + 1, MaxInt)), AKind);
end;

class function TFreeFields.ClassDestructorEdits(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  ClassNode, Child, Declaration, Body, LastConstructor, Decl: TSyntaxNode;
  Lines: TArray<string>;
  LineBreak, Indent, Text, Statement: string;
  Index, Line: Integer;
begin
  AEdits := nil;
  Result := False;
  if (ATree = nil) or (AClassDecl = nil) or (Length(AStatements) = 0) then
    Exit;
  ClassNode := AClassDecl.FindChild(TSyntaxKind.ClassType);
  if ClassNode = nil then
    Exit;
  Lines := TTextLines.SplitLines(AText, LineBreak);
  Declaration := nil;
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    if (Child.Kind = TSyntaxKind.RoutineHeader) and IsClassStructor(AText, Child, 'constructor') then
      Declaration := Child;
  end;
  Body := nil;
  LastConstructor := nil;
  for Decl in ClassMethods(ATree, AClassDecl.Name) do
    if IsClassStructor(AText, HeaderOf(Decl), 'destructor') then
      Body := Decl
    else if IsClassStructor(AText, HeaderOf(Decl), 'constructor') then
      LastConstructor := Decl;
  if Body <> nil then
  begin
    AEdits := [BodyEdit(Lines, Body, AStatements, LineBreak)];
    Exit(True);
  end;
  if (Declaration = nil) or (LastConstructor = nil) then
    Exit;
  // Deklaration in eigener Zeile hinter dem class constructor, gleich eingerückt.
  Line := Declaration.EndPos.Line;
  if Line > High(Lines) then
    Exit;
  Indent := TTextLines.IndentOf(Lines[Declaration.StartPos.Line]);
  AEdits := [InsertAt(TTextPosition.Create(Line, Length(Lines[Line])), LineBreak + Indent +
    'class destructor Destroy;')];
  Indent := StringOfChar(' ', LastConstructor.StartPos.Character);
  Text := Indent + Format('class destructor %s.Destroy;', [Qualifier(AText, LastConstructor, AClassDecl.Name)]) +
    LineBreak + Indent + 'begin';
  for Statement in AStatements do
    Text := Text + LineBreak + Indent + '  ' + Statement;
  Text := Text + LineBreak + Indent + 'end;';
  AEdits := AEdits + [InsertAt(LastConstructor.EndPos, LineBreak + LineBreak + Text)];
  Result := True;
end;

end.
