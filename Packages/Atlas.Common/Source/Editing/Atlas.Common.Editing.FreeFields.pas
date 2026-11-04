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
  Atlas.Common.Editing.FreeFields.Types,
  Atlas.Text.Lines;

const
  FreeMethods: array[0..2] of string = ('Free', 'Destroy', 'DisposeOf');
  /// <summary>Grund für Felder, die ein Interface-Feld übernimmt; sie werden nie gemeldet.</summary>
  InterfaceReason = 'interface';
  /// <summary>Grund für Komponenten mit Owner und Objekte, die eine besitzende Liste übernimmt.</summary>
  OwnedReason = 'owned';
  /// <summary>Listen, die ihre Elemente standardmäßig freigeben (OwnsObjects = True).</summary>
  OwningContainers: array[0..3] of string = ('TObjectList', 'TObjectStack', 'TObjectQueue', 'TComponentList');

type
  /// <summary>Offener Knoten beim Suchen nach Create: Knoten und Methode, in der er steht.</summary>
  TCreationEntry = record
    Node: TSyntaxNode;
    Method: string;
  end;

/// <summary>Methoden, die ein übergebenes Objekt übernehmen können: Add, Insert, Push, Enqueue, Register,
/// Attach und ihre Varianten (AddObject, RegisterListener).</summary>
function HandsOver(const AMethod: string): Boolean;
begin
  Result := StartsText('Add', AMethod) or StartsText('Insert', AMethod) or SameText(AMethod, 'Push') or
    SameText(AMethod, 'Enqueue') or StartsText('Register', AMethod) or StartsText('Attach', AMethod);
end;

/// <summary>Erzeugung mit dem Argument False, z. B. TObjectList&lt;TFoo&gt;.Create(False).</summary>
function CreatedWithFalse(AValue: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (AValue = nil) or (AValue.Kind <> TSyntaxKind.Call) then
  begin
    Exit;
  end;
  for Index := 1 to AValue.ChildCount - 1 do
  begin
    if (AValue[Index].Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
      SameText(AValue[Index].Name, 'False') then
    begin
      Exit(True);
    end;
  end;
end;

function IsSelf(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self');
end;

/// <summary>Name hinter X bzw. Self.X; '' sonst.</summary>
function SelfMemberName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsSelf(ANode[0]) then
  begin
    Result := ANode.Name;
  end;
end;

/// <summary>Namen einer Deklaration "A, B: T" ohne Leerraum.</summary>
function TrimmedNames(const ANames: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames.Split([',']) do
  begin
    Result := Result + [Trim(mName)];
  end;
end;

/// <summary>Bereich des Namens AName in der Felddeklaration AChild; sonst deren Anfang.</summary>
function FieldRange(const ATokens: TArray<TPascalToken>; AChild, ATypeRef: TSyntaxNode; const AName: string):
  TTextRange;
var
  mToken: Integer;
begin
  for mToken := TSyntaxTree.FirstTokenOf(ATokens, AChild.StartOffset) to High(ATokens) do
  begin
    if (ATokens[mToken].Offset >= AChild.StartOffset) and (ATokens[mToken].Offset < ATypeRef.StartOffset) and
      (ATokens[mToken].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mToken].Text, AName) then
    begin
      Exit(TTextRange.Create(ATokens[mToken].StartPos, ATokens[mToken].EndPos));
    end;
  end;
  Result := TTextRange.Create(AChild.StartPos, AChild.StartPos);
end;

/// <summary>Felder der Deklaration AChild (Typ ATypeName) der Klasse ADecl.</summary>
function FieldsOf(ADecl, AChild, ATypeRef: TSyntaxNode; const ATypeName: string;
  const ATokens: TArray<TPascalToken>): TArray<TOwnedField>;
var
  mName: string;
  mField: TOwnedField;
begin
  Result := nil;
  for mName in TrimmedNames(AChild.Name) do
  begin
    mField := Default(TOwnedField);
    mField.ClassName := ADecl.Name;
    mField.ClassLine := ADecl.StartPos.Line;
    mField.Name := mName;
    mField.TypeName := ATypeName;
    mField.Range := FieldRange(ATokens, AChild, ATypeRef, mName);
    mField.Order := -1;
    Result := Result + [mField];
  end;
end;

procedure MarkFreed(AField: Integer; var AFreed: TArray<Boolean>);
begin
  if AField >= 0 then
  begin
    AFreed[AField] := True;
  end;
end;

/// <summary>Liste.Add(…) bzw. Dienst.Register(…) auf einem anderen Objekt als Self.</summary>
function IsHandOver(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.ChildCount >= 2) and (ANode[0].Kind = TSyntaxKind.MemberAccess) and
    (ANode[0].ChildCount = 1) and not IsSelf(ANode[0][0]) and HandsOver(ANode[0].Name);
end;

function IsNilLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and SameText(ANode.Name, 'nil');
end;

/// <summary>Typumwandlung TKlasse(X).</summary>
function IsCastCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier);
end;

/// <summary>X.Create… bzw. X.Create…(Argument): Zugriff auf Create und erstes Argument (nil ohne).</summary>
function CreateCall(AValue: TSyntaxNode; out AAccess, AArgument: TSyntaxNode): Boolean;
begin
  AAccess := nil;
  AArgument := nil;
  if AValue = nil then
  begin
    Exit(False);
  end;
  if (AValue.Kind = TSyntaxKind.Call) and (AValue.ChildCount >= 1) and (AValue[0].Kind = TSyntaxKind.MemberAccess) then
  begin
    AAccess := AValue[0];
    if AValue.ChildCount >= 2 then
    begin
      AArgument := AValue[1];
    end;
  end
  else if AValue.Kind = TSyntaxKind.MemberAccess then
  begin
    AAccess := AValue;
  end;
  Result := (AAccess <> nil) and StartsText('Create', AAccess.Name) and (AAccess.ChildCount >= 1);
end;

/// <summary>Erzeugter Typ vor .Create: Name oder generischer Typ samt Argumenten.</summary>
function ReceiverType(AReceiver: TSyntaxNode; const AText: string; out ATypeName: string): Boolean;
begin
  ATypeName := '';
  if AReceiver.Kind = TSyntaxKind.Identifier then
  begin
    ATypeName := AReceiver.Name;
  end
  else if (AReceiver.Kind = TSyntaxKind.MemberAccess) and (AReceiver.ChildCount >= 2) and
    (AReceiver[0].Kind = TSyntaxKind.Identifier) and (AReceiver[1].Kind = TSyntaxKind.GenericArgs) then
  begin
    ATypeName := TFreeFieldTypes.CodeOf(AText, AReceiver);
  end;
  Result := ATypeName <> '';
end;

/// <summary>Feld, das eine Property mit "write FFeld" setzt; '' sonst.</summary>
function WrittenField(const AText: string; AChild: TSyntaxNode): string;
var
  mMatch: TMatch;
begin
  Result := '';
  if AChild.Kind = TSyntaxKind.PropertyDecl then
  begin
    mMatch := TRegEx.Match(TFreeFieldTypes.NodeText(AText, AChild), '\bwrite\s+(\w+)', [roIgnoreCase]);
    if mMatch.Success then
    begin
      Result := mMatch.Groups[1].Value;
    end;
  end;
end;

{ TClassAnalyzer }

type
  /// <summary>Lokale Kopie eines Felds in der gerade durchsuchten Methode (Writer := FWriter).</summary>
  TFieldAlias = record
    Name: string;
    Field: Integer;
  end;

  TClassAnalyzer = class
  private
    FTree: TSyntaxTree;
    FText: string;
    FTypes: TFreeFieldTypes;
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
    FAliases: TArray<TFieldAlias>;
    FCurrent: string;
    /// <summary>Feld hinter ANode, auch über eine lokale Kopie; sonst -1.</summary>
    function FreedRef(ANode: TSyntaxNode): Integer;
    function FieldIndex(const AName: string): Integer;
    function FieldRef(ANode: TSyntaxNode): Integer;
    /// <summary>ANode ist FFeld oder Self.FFeld mit einem Interface-Typ.</summary>
    function IsInterfaceField(ANode: TSyntaxNode): Boolean;
    function MethodBody(const AName: string): TSyntaxNode;
    function CalledPrivate(AStatement: TSyntaxNode): string;
    /// <summary>Übernimmt AReceiver.Add…(Feld AField) das Objekt? Ja, wenn AReceiver ein Feld ist, das selbst
    /// eine besitzende Liste für den Typ von AField ist oder eine solche als Feld hat.</summary>
    function TakesOver(AReceiver: TSyntaxNode; AField: Integer): Boolean;
    procedure NoteCreation(ANode: TSyntaxNode);
    procedure PushCalled(ANode: TSyntaxNode; APending: TStack<TCreationEntry>);
    procedure ScanCreations(ANode: TSyntaxNode);
    procedure ScanUses(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
    procedure CheckUse(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
    procedure CheckCall(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
    procedure CheckHandOver(ANode: TSyntaxNode; const AMethod: string);
    procedure CheckAssign(ANode: TSyntaxNode; const AMethod: string);
    procedure NoteCopy(ATarget: TSyntaxNode; AField: Integer; const AMethod: string);
    procedure SetUnclear(AField: Integer; const AReason: string);
    procedure ReadField(AChild: TSyntaxNode);
    procedure ReadClass;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex; ADecl: TSyntaxNode);
    destructor Destroy; override;
    function Creation(AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
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
  begin
    Section := ATree.Root;
  end;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if Section[Index].Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + [Section[Index]];
    end;
  end;
end;

/// <summary>Methoden TKlasse.Name mit Rumpf, ohne Methoden verschachtelter Klassen.</summary>
function ClassMethods(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>;
var
  Decl: TSyntaxNode;
  Rest: string;
begin
  Result := nil;
  for Decl in RoutineDecls(ATree) do
  begin
    if StartsText(AClassName + '.', Decl.Name) and (Decl.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Rest := Copy(Decl.Name, Length(AClassName) + 2, MaxInt);
      if (Rest <> '') and (Pos('.', Rest) = 0) then
      begin
        Result := Result + [Decl];
      end;
    end;
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
  Result := (Header <> nil) and StartsWithWord(TFreeFieldTypes.NodeText(AText, Header), 'constructor');
end;

function IsDestructorHeader(const AText: string; AHeader: TSyntaxNode): Boolean;
begin
  Result := (AHeader <> nil) and SameText(AHeader.Name, 'Destroy') and
    StartsWithWord(TFreeFieldTypes.NodeText(AText, AHeader), 'destructor');
end;

constructor TClassAnalyzer.Create(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  ADecl: TSyntaxNode);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FTypes := TFreeFieldTypes.Create(ATree, AText, AIndex);
  // Ohne Klasse (ADecl = nil) nur für Typen und Erzeugungen außerhalb von Klassen (#971).
  if ADecl = nil then
  begin
    Exit;
  end;
  FClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  FClassName := ADecl.Name;
end;

destructor TClassAnalyzer.Destroy;
begin
  FTypes.Free;
  inherited Destroy;
end;

function TClassAnalyzer.FieldIndex(const AName: string): Integer;
var
  mIndex: Integer;
begin
  if AName <> '' then
  begin
    for mIndex := 0 to High(FFields) do
    begin
      if SameText(FFields[mIndex].Name, AName) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

function TClassAnalyzer.FreedRef(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := FieldRef(ANode);
  if (Result >= 0) or (ANode = nil) or (ANode.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  for mIndex := High(FAliases) downto 0 do
  begin
    if SameText(FAliases[mIndex].Name, ANode.Name) then
    begin
      Exit(FAliases[mIndex].Field);
    end;
  end;
end;

function TClassAnalyzer.FieldRef(ANode: TSyntaxNode): Integer;
begin
  Result := FieldIndex(SelfMemberName(ANode));
end;

function TClassAnalyzer.IsInterfaceField(ANode: TSyntaxNode): Boolean;
var
  mName: string;
begin
  mName := SelfMemberName(ANode);
  Result := (mName <> '') and MatchText(mName, FInterfaceFields);
end;

function TClassAnalyzer.MethodBody(const AName: string): TSyntaxNode;
var
  mDecl: TSyntaxNode;
begin
  for mDecl in FMethods do
  begin
    if SameText(mDecl.Name, FClassName + '.' + AName) then
    begin
      Exit(mDecl);
    end;
  end;
  Result := nil;
end;

function TClassAnalyzer.Creation(AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
var
  mAccess, mArgument: TSyntaxNode;
begin
  ATypeName := '';
  AOwned := False;
  Result := CreateCall(AValue, mAccess, mArgument) and ReceiverType(mAccess[0], FText, ATypeName) and
    not SameText(ATypeName, 'Self') and (FieldIndex(ATypeName) < 0) and
    not (FTypes.TypeGuess(ATypeName) in [tgRecord, tgInterface, tgOther]);
  if not Result then
  begin
    ATypeName := '';
  end
  // Owner ungleich nil: die Komponente gibt ihr Owner frei. Owner ist auch ein Komponentenfeld der Klasse
  // (Host := TForm.Create…; Box := TFoo.Create(Host)).
  else if (mArgument <> nil) and not IsNilLiteral(mArgument) then
  begin
    AOwned := FTypes.OwnedByArgument(ATypeName, mArgument) or
      ((FieldRef(mArgument) >= 0) and FTypes.IsComponent(FFields[FieldRef(mArgument)].TypeName));
  end;
end;

function TClassAnalyzer.CalledPrivate(AStatement: TSyntaxNode): string;
var
  mTarget: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount < 1) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount >= 1) then
  begin
    mTarget := mTarget[0];
  end;
  Result := SelfMemberName(mTarget);
  if IndexText(Result, FPrivate) < 0 then
  begin
    Result := '';
  end;
end;

/// <summary>Besitzende Liste AContainer, deren Elementtyp einer aus AElements ist (ohne Typargument: jedes
/// Objekt).</summary>
function OwnsElements(const AContainer: string; const AElements: TArray<string>): Boolean;
var
  mArgs: string;
begin
  Result := MatchText(TFreeFieldTypes.BaseName(AContainer), OwningContainers);
  if not Result or (Pos('<', AContainer) = 0) then
  begin
    Exit;
  end;
  mArgs := Copy(AContainer, Pos('<', AContainer) + 1, MaxInt);
  if EndsText('>', mArgs) then
  begin
    mArgs := Copy(mArgs, 1, Length(mArgs) - 1);
  end;
  Result := MatchText(TFreeFieldTypes.BaseName(mArgs), AElements);
end;

function ContainsInteger(const AItems: TArray<Integer>; AValue: Integer): Boolean;
var
  mItem: Integer;
begin
  for mItem in AItems do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TClassAnalyzer.TakesOver(AReceiver: TSyntaxNode; AField: Integer): Boolean;
var
  mReceiver: Integer;
  mElements: TArray<string>;
  mEndsKnown: Boolean;
  mFieldType: string;
begin
  mReceiver := FieldRef(AReceiver);
  if (mReceiver < 0) or (AField < 0) then
  begin
    Exit(False);
  end;
  mFieldType := FFields[AField].CreatedType;
  if mFieldType = '' then
  begin
    mFieldType := FFields[AField].TypeName;
  end;
  mElements := FTypes.ComponentChain(mFieldType, mEndsKnown) +
    [TFreeFieldTypes.BaseName(FFields[AField].TypeName), 'TObject'];
  // TObjectList.Create(False) besitzt nichts.
  if OwnsElements(FFields[mReceiver].TypeName, mElements) then
  begin
    Exit(not ContainsInteger(FNotOwning, mReceiver));
  end;
  for mFieldType in FTypes.ClassFieldTypes(TFreeFieldTypes.BaseName(FFields[mReceiver].TypeName)) do
  begin
    if OwnsElements(mFieldType, mElements) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TClassAnalyzer.NoteCreation(ANode: TSyntaxNode);
var
  mField: Integer;
  mTypeName: string;
  mOwned: Boolean;
begin
  if (ANode.Kind <> TSyntaxKind.AssignStatement) or (ANode.ChildCount < 2) then
  begin
    Exit;
  end;
  mField := FieldRef(ANode[0]);
  if (mField < 0) or (FFields[mField].CreatedIn <> '') or not Creation(ANode[1], mTypeName, mOwned) then
  begin
    Exit;
  end;
  FFields[mField].CreatedIn := FCurrent;
  FFields[mField].CreatedType := mTypeName;
  FFields[mField].Order := Length(FCreated);
  FCreated := FCreated + [mField];
  // Komponenten mit Owner gelten als erzeugt, aber nicht als eigen.
  if mOwned then
  begin
    FFields[mField].Reason := OwnedReason;
  end;
  if CreatedWithFalse(ANode[1]) then
  begin
    FNotOwning := FNotOwning + [mField];
  end;
end;

procedure TClassAnalyzer.PushCalled(ANode: TSyntaxNode; APending: TStack<TCreationEntry>);
var
  mCalled: string;
  mBody: TSyntaxNode;
  mNext: TCreationEntry;
begin
  mCalled := CalledPrivate(ANode);
  if (mCalled = '') or (IndexText(mCalled, FVisited) >= 0) then
  begin
    Exit;
  end;
  FVisited := FVisited + [mCalled];
  mBody := MethodBody(mCalled);
  if mBody <> nil then
  begin
    mNext.Node := mBody.FindChild(TSyntaxKind.Block);
    mNext.Method := mBody.Name;
    APending.Push(mNext);
  end;
end;

procedure TClassAnalyzer.ScanCreations(ANode: TSyntaxNode);
var
  mPending: TStack<TCreationEntry>;
  mEntry, mNext: TCreationEntry;
  mIndex: Integer;
  mSaved: string;
begin
  // Eigener Stapel statt Rekursion: Lange Ausdrucksketten dürfen den Aufrufstapel nicht
  // erschöpfen. Die Reihenfolge bleibt die der Rekursion: Knoten, dann der Rumpf einer
  // aufgerufenen privaten Methode, dann die Kinder von links nach rechts.
  mSaved := FCurrent;
  mPending := TStack<TCreationEntry>.Create;
  try
    mEntry.Node := ANode;
    mEntry.Method := FCurrent;
    mPending.Push(mEntry);
    while mPending.Count > 0 do
    begin
      mEntry := mPending.Pop;
      if (mEntry.Node = nil) or (mEntry.Node.Kind = TSyntaxKind.AnonymousMethod) then
      begin
        Continue;
      end;
      FCurrent := mEntry.Method;
      NoteCreation(mEntry.Node);
      mNext.Method := mEntry.Method;
      for mIndex := mEntry.Node.ChildCount - 1 downto 0 do
      begin
        mNext.Node := mEntry.Node[mIndex];
        mPending.Push(mNext);
      end;
      // Zuletzt abgelegt, also vor den Kindern durchsucht.
      PushCalled(mEntry.Node, mPending);
    end;
  finally
    mPending.Free;
    FCurrent := mSaved;
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
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  FAliases := nil;
  // Eigener Stapel statt Rekursion, damit tiefe Ausdrücke den Aufrufstapel nicht erschöpfen.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode = nil then
      begin
        Continue;
      end;
      CheckUse(mNode, AMethod, AFreed);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TClassAnalyzer.CheckUse(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
begin
  case ANode.Kind of
    TSyntaxKind.MemberAccess:
      if (ANode.ChildCount >= 1) and MatchText(ANode.Name, FreeMethods) then
      begin
        MarkFreed(FreedRef(ANode[0]), AFreed);
      end;
    TSyntaxKind.Call:
      CheckCall(ANode, AMethod, AFreed);
    TSyntaxKind.AssignStatement:
      if ANode.ChildCount >= 2 then
      begin
        CheckAssign(ANode, AMethod);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TClassAnalyzer.CheckCall(ANode: TSyntaxNode; const AMethod: string; var AFreed: TArray<Boolean>);
begin
  if (ANode.ChildCount = 2) and (ANode[0].Kind = TSyntaxKind.Identifier) then
  begin
    if SameText(ANode[0].Name, 'FreeAndNil') then
    begin
      MarkFreed(FreedRef(ANode[1]), AFreed);
    end
    else if SameText(ANode[0].Name, 'Exit') then
    begin
      SetUnclear(FieldRef(ANode[1]), Format('wird von %s zurückgegeben', [AMethod]));
    end;
  end
  else if IsHandOver(ANode) then
  begin
    CheckHandOver(ANode, AMethod);
  end;
end;

procedure TClassAnalyzer.CheckHandOver(ANode: TSyntaxNode; const AMethod: string);
var
  mIndex, mField: Integer;
begin
  // Liste.Add(FFeld), Dienst.Register(FFeld): das andere Objekt kann es übernehmen (#918). Besitzt es
  // seine Elemente (TObjectList oder eine Klasse mit einer), gibt es das Objekt frei.
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mField := FieldRef(ANode[mIndex]);
    if TakesOver(ANode[0][0], mField) then
    begin
      FFields[mField].State := TOwnedFieldState.NotFreed;
      FFields[mField].Reason := OwnedReason;
    end
    else
    begin
      SetUnclear(mField, Format('wird in %s an %s übergeben', [AMethod, TFreeFieldTypes.CodeOf(FText, ANode[0])]));
    end;
  end;
end;

procedure TClassAnalyzer.NoteCopy(ATarget: TSyntaxNode; AField: Integer; const AMethod: string);
var
  mAlias: TFieldAlias;
begin
  if (ATarget.Kind = TSyntaxKind.Identifier) and SameText(ATarget.Name, 'Result') then
  begin
    SetUnclear(AField, Format('wird von %s zurückgegeben', [AMethod]));
  end
  else if (ATarget.Kind = TSyntaxKind.Identifier) and (FieldRef(ATarget) < 0) then
  begin
    // Lokale Kopie: Gibt die Methode sie frei, ist das Feld freigegeben.
    mAlias.Name := ATarget.Name;
    mAlias.Field := AField;
    FAliases := FAliases + [mAlias];
  end
  else if (ATarget.Kind = TSyntaxKind.MemberAccess) and (FieldRef(ATarget) < 0) then
  begin
    SetUnclear(AField, Format('wird in %s an %s übergeben', [AMethod, TFreeFieldTypes.CodeOf(FText, ATarget)]));
  end;
end;

procedure TClassAnalyzer.CheckAssign(ANode: TSyntaxNode; const AMethod: string);
var
  mTarget: TSyntaxNode;
  mField: Integer;
  mTypeName: string;
  mOwned: Boolean;
begin
  mTarget := ANode[0];
  mField := FieldRef(ANode[1]);
  // Typumwandlung TKlasse(FFeld) zählt wie FFeld.
  if (mField < 0) and IsCastCall(ANode[1]) and IsInterfaceField(mTarget) then
  begin
    mField := FieldRef(ANode[1][1]);
  end;
  if (mField >= 0) and IsInterfaceField(mTarget) then
  begin
    // Das Interface-Feld übernimmt das Objekt; Free wäre eine doppelte Freigabe.
    FFields[mField].State := TOwnedFieldState.NotFreed;
    FFields[mField].Reason := InterfaceReason;
  end
  else if mField >= 0 then
  begin
    NoteCopy(mTarget, mField, AMethod);
  end;
  mField := FieldRef(mTarget);
  if (mField >= 0) and not Creation(ANode[1], mTypeName, mOwned) and not IsNilLiteral(ANode[1]) then
  begin
    SetUnclear(mField, Format('wird in %s auch ohne Create zugewiesen', [AMethod]));
  end;
end;

procedure TClassAnalyzer.ReadField(AChild: TSyntaxNode);
var
  mTypeRef: TSyntaxNode;
  mTypeName: string;
  mGuess: TTypeGuess;
begin
  mTypeRef := AChild.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef = nil then
  begin
    Exit;
  end;
  mTypeName := TFreeFieldTypes.CodeOf(FText, mTypeRef);
  mGuess := FTypes.TypeGuess(mTypeName);
  if mGuess = tgInterface then
  begin
    FInterfaceFields := FInterfaceFields + TrimmedNames(AChild.Name);
  end;
  if not (mGuess in [tgRecord, tgInterface, tgOther]) then
  begin
    FFields := FFields + FieldsOf(FClassNode.Parent, AChild, mTypeRef, mTypeName, FTree.Tokens);
  end;
end;

procedure TClassAnalyzer.ReadClass;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mSection: string;
begin
  mSection := 'public';
  for mIndex := 0 to FClassNode.ChildCount - 1 do
  begin
    mChild := FClassNode[mIndex];
    case mChild.Kind of
      TSyntaxKind.Visibility:
        mSection := mChild.Name;
      TSyntaxKind.RoutineHeader:
        if EndsText('private', mSection) then
        begin
          FPrivate := FPrivate + [mChild.Name];
        end;
      TSyntaxKind.Field:
        ReadField(mChild);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

function TClassAnalyzer.Fields: TArray<TOwnedField>;
var
  mDecl: TSyntaxNode;
  mFreed: TArray<Boolean>;
  mIndex: Integer;
  mWritten: string;
begin
  Result := nil;
  if FClassNode = nil then
  begin
    Exit;
  end;
  ReadClass;
  FMethods := ClassMethods(FTree, FClassName);
  for mDecl in FMethods do
  begin
    if (FFields <> nil) and IsConstructorDecl(FText, mDecl) then
    begin
      FCurrent := mDecl.Name;
      FVisited := nil;
      ScanCreations(mDecl.FindChild(TSyntaxKind.Block));
    end;
  end;
  if FCreated = nil then
  begin
    Exit;
  end;
  SetLength(mFreed, Length(FFields));
  for mDecl in FMethods do
  begin
    ScanUses(mDecl.FindChild(TSyntaxKind.Block), mDecl.Name, mFreed);
  end;
  // write FFeld: Das Objekt kann von außen kommen.
  for mIndex := 0 to FClassNode.ChildCount - 1 do
  begin
    mWritten := WrittenField(FText, FClassNode[mIndex]);
    if mWritten <> '' then
    begin
      SetUnclear(FieldIndex(mWritten), Format('kann über die Property %s von außen gesetzt werden',
        [FClassNode[mIndex].Name]));
    end;
  end;
  for mIndex in FCreated do
  begin
    if not mFreed[mIndex] and (FFields[mIndex].Reason <> OwnedReason) and
      (FFields[mIndex].Reason <> InterfaceReason) then
    begin
      Result := Result + [FFields[mIndex]];
    end;
  end;
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
      begin
        Found := ANode;
      end;
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
  begin
    if IsDestructorHeader(AText, ClassNode[Index]) and (ClassNode[Index].Kind = TSyntaxKind.RoutineHeader) then
    begin
      Result.Declaration := ClassNode[Index];
    end;
  end;
  for Decl in ClassMethods(ATree, ADecl.Name) do
  begin
    Header := HeaderOf(Decl);
    if SameText(Decl.Name, ADecl.Name + '.Destroy') and (Header <> nil) and
      StartsWithWord(TFreeFieldTypes.NodeText(AText, Header), 'destructor') then
    begin
      Result.Body := Decl;
    end
    else if IsConstructorDecl(AText, Decl) then
    begin
      Result.LastConstructor := Decl;
    end;
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
  Header := TFreeFieldTypes.Collapse(Copy(AText, AConstructor.StartOffset + 1,
    AConstructor.FindChild(TSyntaxKind.Block).StartOffset - AConstructor.StartOffset));
  // "constructor" bzw. "class constructor" (#971) abschneiden.
  Header := Trim(Copy(Header, Pos('constructor', LowerCase(Header)) + Length('constructor'), MaxInt));
  Stop := Pos('(', Header);
  if Stop = 0 then
  begin
    Stop := Pos(';', Header);
  end;
  if Stop > 0 then
  begin
    Header := Copy(Header, 1, Stop - 1);
  end;
  Stop := LastDelimiter('.', Header);
  Result := AClassName;
  if Stop > 1 then
  begin
    Result := Trim(Copy(Header, 1, Stop - 1));
  end;
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
  begin
    Prefix := Copy(ALines[Position.Line], 1, Position.Character);
  end;
  Text := '';
  if Trim(Prefix) = '' then
  begin
    // Eigene Zeilen vor der Ankerzeile, eingerückt wie sie (bzw. eine Stufe tiefer als "end").
    Indent := Prefix + Indent;
    for Statement in AStatements do
    begin
      Text := Text + Indent + Statement + ALineBreak;
    end;
    Result := InsertAt(TTextPosition.Create(Position.Line, 0), Text);
  end
  else
  begin
    for Statement in AStatements do
    begin
      Text := Text + Statement + ' ';
    end;
    Result := InsertAt(Position, Text);
  end;
end;

function IsConstructorHeader(const AText: string; AChild: TSyntaxNode): Boolean;
begin
  Result := (AChild.Kind = TSyntaxKind.RoutineHeader) and
    StartsWithWord(TFreeFieldTypes.NodeText(AText, AChild), 'constructor');
end;

/// <summary>Mitglied im public-Abschnitt, hinter das der Destruktor kommt: der letzte Konstruktor, sonst das
/// letzte Mitglied; nil ohne. APublicHead: das Schlüsselwort des letzten public-Abschnitts.</summary>
function PublicAnchor(const AText: string; AClassNode: TSyntaxNode; out APublicHead: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mChild, mAfterConstructor: TSyntaxNode;
  mInPublic: Boolean;
begin
  Result := nil;
  mAfterConstructor := nil;
  APublicHead := nil;
  mInPublic := False;
  for mIndex := 0 to AClassNode.ChildCount - 1 do
  begin
    mChild := AClassNode[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      mInPublic := SameText(mChild.Name, 'public');
      if mInPublic then
      begin
        APublicHead := mChild;
        Result := nil;
      end;
    end
    else if mInPublic and (mChild.Kind <> TSyntaxKind.TypeReference) then
    begin
      Result := mChild;
      if IsConstructorHeader(AText, mChild) then
      begin
        mAfterConstructor := mChild;
      end;
    end;
  end;
  if mAfterConstructor <> nil then
  begin
    Result := mAfterConstructor;
  end;
end;

/// <summary>AText am Ende der Zeile ALine einfügen.</summary>
function AppendLine(const ALines: TArray<string>; ALine: Integer; const AText: string): TTextEdit;
begin
  Result := InsertAt(TTextPosition.Create(ALine, Length(ALines[ALine])), AText);
end;

/// <summary>"destructor Destroy; override;" in den public-Abschnitt; False, wenn kein Platz zu finden ist.</summary>
function DeclarationEdit(const ALines: TArray<string>; const AText: string; ADecl: TSyntaxNode;
  const ALineBreak: string; out AEdit: TTextEdit): Boolean;
const
  cDeclaration = 'destructor Destroy; override;';
var
  mClassNode, mLast, mHead: TSyntaxNode;
  mLine: Integer;
  mIndent: string;
begin
  mClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  mLast := PublicAnchor(AText, mClassNode, mHead);
  if mLast <> nil then
  begin
    AEdit := AppendLine(ALines, mLast.EndPos.Line, ALineBreak + TTextLines.IndentOf(ALines[mLast.StartPos.Line]) +
      cDeclaration);
    Exit(True);
  end;
  if mHead <> nil then
  begin
    AEdit := AppendLine(ALines, mHead.EndPos.Line, ALineBreak + TTextLines.IndentOf(ALines[mHead.StartPos.Line]) +
      '  ' + cDeclaration);
    Exit(True);
  end;
  // Neuer Abschnitt vor dem "end" der Klasse, wenn es allein auf seiner Zeile steht.
  mLine := mClassNode.EndPos.Line;
  Result := (mLine <= High(ALines)) and (Trim(Copy(ALines[mLine], 1, mClassNode.EndPos.Character - 3)) = '');
  if Result then
  begin
    mIndent := TTextLines.IndentOf(ALines[mLine]);
    AEdit := InsertAt(TTextPosition.Create(mLine, 0), mIndent + 'public' + ALineBreak + mIndent + '  ' +
      cDeclaration + ALineBreak);
  end;
end;

/// <summary>Routine mit Kopf AHeader und den Anweisungen AStatements, eingerückt um AIndent.</summary>
function RoutineText(const AIndent, AHeader: string; const AStatements: TArray<string>;
  const ALineBreak: string): string;
var
  mStatement: string;
begin
  Result := AIndent + AHeader + ALineBreak + AIndent + 'begin';
  for mStatement in AStatements do
  begin
    Result := Result + ALineBreak + AIndent + '  ' + mStatement;
  end;
  Result := Result + ALineBreak + AIndent + 'end;';
end;

/// <summary>Neuer Destruktor hinter dem letzten Konstruktor, samt Deklaration, wenn sie fehlt.</summary>
function NewDestructor(const AText: string; ADecl: TSyntaxNode; const APlace: TDestructorPlace;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mHeader: string;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  if APlace.LastConstructor = nil then
  begin
    Exit(False);
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  if APlace.Declaration = nil then
  begin
    if not DeclarationEdit(mLines, AText, ADecl, mLineBreak, mEdit) then
    begin
      Exit(False);
    end;
    AEdits := [mEdit];
  end;
  mHeader := Format('destructor %s.Destroy;', [Qualifier(AText, APlace.LastConstructor, ADecl.Name)]);
  AEdits := AEdits + [InsertAt(APlace.LastConstructor.EndPos, mLineBreak + mLineBreak +
    RoutineText(StringOfChar(' ', APlace.LastConstructor.StartPos.Character), mHeader, AStatements + ['inherited;'],
    mLineBreak))];
  Result := True;
end;

{ TFreeFields }

class function TFreeFields.StyleOf(const AName: string): TFreeFieldsStyle;
begin
  if SameText(AName, 'freeAndNil') then
  begin
    Result := TFreeFieldsStyle.FreeAndNil;
  end
  else
  begin
    Result := TFreeFieldsStyle.Free;
  end;
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
  begin
    Exit;
  end;
  Decls := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // Klassen in Typabschnitten; verschachtelte Klassen nicht.
      Result := ANode.Kind <> TSyntaxKind.ClassType;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        Decls := Decls + [ANode];
      end;
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
  begin
    Result := Format('FreeAndNil(%s);', [AField]);
  end
  else
  begin
    Result := AField + '.Free;';
  end;
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
  begin
    Exit;
  end;
  // Umgekehrte Erzeugungsreihenfolge.
  Order := nil;
  for Index := 0 to High(AFields) do
  begin
    Order := Order + [Index];
  end;
  for Index := 0 to High(Order) - 1 do
  begin
    for Other := Index + 1 to High(Order) do
    begin
      if AFields[Order[Other]].Order > AFields[Order[Index]].Order then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Other];
        Order[Other] := Swap;
      end;
    end;
  end;
  Statements := nil;
  for Index in Order do
  begin
    Statements := Statements + [Statement(AFields[Index].Name, AStyle)];
  end;
  Result := DestructorEdits(ATree, AText, AFields[0].ClassName, AFields[0].ClassLine, Statements, AEdits);
end;

class function TFreeFields.DestructorEdits(ATree: TSyntaxTree; const AText, AClassName: string; ALine: Integer;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mDecl: TSyntaxNode;
  mPlace: TDestructorPlace;
  mLines: TArray<string>;
  mLineBreak: string;
begin
  AEdits := nil;
  mDecl := nil;
  if (ATree <> nil) and (ATree.Root <> nil) and (Length(AStatements) > 0) then
  begin
    mDecl := FindClassDecl(ATree, AClassName, ALine);
  end;
  if mDecl = nil then
  begin
    Exit(False);
  end;
  mPlace := PlaceOf(ATree, AText, mDecl);
  if mPlace.Body = nil then
  begin
    Exit(NewDestructor(AText, mDecl, mPlace, AStatements, AEdits));
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  AEdits := [BodyEdit(mLines, mPlace.Body, AStatements, mLineBreak)];
  Result := True;
end;

/// <summary>Treffer auf Zeile ALine: ein nicht freigegebenes Feld dort oder die Kopfzeile seiner Klasse.</summary>
function FindHit(const AAll: TArray<TOwnedField>; ALine: Integer; out AHit: TOwnedField;
  out AOnField, AOnClass: Boolean): Boolean;
var
  mField: TOwnedField;
begin
  AHit := Default(TOwnedField);
  AOnField := False;
  AOnClass := False;
  for mField in AAll do
  begin
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.Range.StartPos.Line = ALine) then
    begin
      AHit := mField;
      AOnField := True;
      Break;
    end;
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.ClassLine = ALine) then
    begin
      AHit := mField;
      AOnClass := True;
    end;
  end;
  Result := AOnField or AOnClass;
end;

/// <summary>Nicht freigegebene Felder der Klasse von AHit.</summary>
function FieldsOfClass(const AAll: TArray<TOwnedField>; const AHit: TOwnedField): TArray<TOwnedField>;
var
  mField: TOwnedField;
begin
  Result := nil;
  for mField in AAll do
  begin
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.ClassLine = AHit.ClassLine) and
      SameText(mField.ClassName, AHit.ClassName) then
    begin
      Result := Result + [mField];
    end;
  end;
end;

function FixAction(const ATitle: string; const AEdits: TArray<TTextEdit>; APreferred: Boolean): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := ATitle;
  Result.Kind := QuickFixKind;
  Result.Edits := AEdits;
  Result.IsPreferred := APreferred;
end;

class function TFreeFields.Actions(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  ALine: Integer; AStyle: TFreeFieldsStyle; AWithFieldAction: Boolean): TArray<TCodeAction>;
var
  mAll, mOfClass: TArray<TOwnedField>;
  mHit: TOwnedField;
  mOnField, mOnClass: Boolean;
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  mAll := Analyze(ATree, AText, AIndex);
  if not FindHit(mAll, ALine, mHit, mOnField, mOnClass) then
  begin
    Exit;
  end;
  mOfClass := FieldsOfClass(mAll, mHit);
  if mOnField and AWithFieldAction and Edits(ATree, AText, TArray<TOwnedField>.Create(mHit), AStyle, mEdits) then
  begin
    Result := Result + [FixAction(FieldTitle, mEdits, True)];
  end;
  if (mOnClass or (Length(mOfClass) >= 2)) and Edits(ATree, AText, mOfClass, AStyle, mEdits) then
  begin
    Result := Result + [FixAction(Format(ClassTitle, [Length(mOfClass)]), mEdits, False)];
  end;
end;

class function TFreeFields.ObjectCreation(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  AValue: TSyntaxNode; out ATypeName: string; out AOwned: Boolean): Boolean;
var
  mAnalyzer: TClassAnalyzer;
begin
  mAnalyzer := TClassAnalyzer.Create(ATree, AText, AIndex, nil);
  try
    Result := mAnalyzer.Creation(AValue, ATypeName, AOwned);
  finally
    mAnalyzer.Free;
  end;
end;

class function TFreeFields.IsObjectType(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  const ATypeName: string): Boolean;
var
  mTypes: TFreeFieldTypes;
begin
  mTypes := TFreeFieldTypes.Create(ATree, AText, AIndex);
  try
    Result := not (mTypes.TypeGuess(ATypeName) in [tgRecord, tgInterface, tgOther]);
  finally
    mTypes.Free;
  end;
end;

/// <summary>Beginnt der Kopf mit "class constructor" bzw. "class destructor" (AKind)?</summary>
function IsClassStructor(const AText: string; AHeader: TSyntaxNode; const AKind: string): Boolean;
var
  mText: string;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  mText := TFreeFieldTypes.CodeOf(AText, AHeader);
  Result := StartsWithWord(mText, 'class') and StartsWithWord(Trim(Copy(mText, Length('class') + 1, MaxInt)), AKind);
end;

/// <summary>Deklaration des class constructor in der Klasse; nil ohne.</summary>
function ClassConstructorDecl(const AText: string; AClassNode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AClassNode.ChildCount - 1 do
  begin
    if (AClassNode[mIndex].Kind = TSyntaxKind.RoutineHeader) and
      IsClassStructor(AText, AClassNode[mIndex], 'constructor') then
    begin
      Result := AClassNode[mIndex];
    end;
  end;
end;

/// <summary>Rümpfe des class destructor und des letzten class constructor; nil ohne.</summary>
procedure ClassStructorBodies(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
  out ABody, ALastConstructor: TSyntaxNode);
var
  mDecl: TSyntaxNode;
begin
  ABody := nil;
  ALastConstructor := nil;
  for mDecl in ClassMethods(ATree, AClassDecl.Name) do
  begin
    if IsClassStructor(AText, HeaderOf(mDecl), 'destructor') then
    begin
      ABody := mDecl;
    end
    else if IsClassStructor(AText, HeaderOf(mDecl), 'constructor') then
    begin
      ALastConstructor := mDecl;
    end;
  end;
end;

class function TFreeFields.ClassDestructorEdits(ATree: TSyntaxTree; const AText: string; AClassDecl: TSyntaxNode;
  const AStatements: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mDeclaration, mBody, mLast: TSyntaxNode;
  mLines: TArray<string>;
  mLineBreak, mHeader: string;
begin
  AEdits := nil;
  if (ATree = nil) or (AClassDecl = nil) or (Length(AStatements) = 0) or
    (AClassDecl.FindChild(TSyntaxKind.ClassType) = nil) then
  begin
    Exit(False);
  end;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  ClassStructorBodies(ATree, AText, AClassDecl, mBody, mLast);
  if mBody <> nil then
  begin
    AEdits := [BodyEdit(mLines, mBody, AStatements, mLineBreak)];
    Exit(True);
  end;
  mDeclaration := ClassConstructorDecl(AText, AClassDecl.FindChild(TSyntaxKind.ClassType));
  // Deklaration in eigener Zeile hinter dem class constructor, gleich eingerückt.
  Result := (mDeclaration <> nil) and (mLast <> nil) and (mDeclaration.EndPos.Line <= High(mLines));
  if Result then
  begin
    mHeader := Format('class destructor %s.Destroy;', [Qualifier(AText, mLast, AClassDecl.Name)]);
    AEdits := [AppendLine(mLines, mDeclaration.EndPos.Line, mLineBreak +
      TTextLines.IndentOf(mLines[mDeclaration.StartPos.Line]) + 'class destructor Destroy;'),
      InsertAt(mLast.EndPos, mLineBreak + mLineBreak + RoutineText(StringOfChar(' ', mLast.StartPos.Character),
      mHeader, AStatements, mLineBreak))];
  end;
end;

end.
