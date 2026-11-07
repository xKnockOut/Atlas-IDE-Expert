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
//     Interface-Feld zuweist (FLog := FLogImpl) oder einem Interface-Feld eines
//     Record-Felds (FSystem.Registry := FRegistry, #1519): die Referenzzählung
//     gibt sie frei (#918). TObjectList und TObjectDictionary sind normale Felder.
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
  public
    class function FieldTitle: string; static;
    class function ClassTitle: string; static;
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
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFreeFieldsText = (IsReturnedBy, IsPassedTo1In, IsAlsoAssignedWithoutCreate, CanBeSetFromOutside,
    FreeInTheDestructor, FreeAllOwnedObjects);

const
  cTexts: array[TFreeFieldsText] of TAtlasText = (
    (De: 'wird von %s zurückgegeben'; En: 'is returned by %s'),
    (De: 'wird in %s an %s übergeben'; En: 'is passed to %1:s in %0:s'),
    (De: 'wird in %s auch ohne Create zugewiesen'; En: 'is also assigned without Create in %s'),
    (De: 'kann über die Property %s von außen gesetzt werden'; En: 'can be set from outside via the property %s'),
    (De: 'Im Destruktor freigeben'; En: 'Free in the destructor'),
    (De: 'Alle eigenen Objekte freigeben (%d)'; En: 'Free all owned objects (%d)'));

{$SCOPEDENUMS OFF}

class function TFreeFields.FieldTitle: string;
begin
  Result := cTexts[TFreeFieldsText.FreeInTheDestructor].Text;
end;

class function TFreeFields.ClassTitle: string;
begin
  Result := cTexts[TFreeFieldsText.FreeAllOwnedObjects].Text;
end;

const
  cFreeMethods: array[0..2] of string = ('Free', 'Destroy', 'DisposeOf');
  /// <summary>Grund für Felder, die ein Interface-Feld übernimmt; sie werden nie gemeldet.</summary>
  cInterfaceReason = 'interface';
  /// <summary>Grund für Komponenten mit Owner und Objekte, die eine besitzende Liste übernimmt.</summary>
  cOwnedReason = 'owned';
  /// <summary>Listen, die ihre Elemente standardmäßig freigeben (OwnsObjects = True).</summary>
  cOwningContainers: array[0..3] of string = ('TObjectList', 'TObjectStack', 'TObjectQueue', 'TComponentList');

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
  mIndex: Integer;
begin
  Result := False;
  if (AValue = nil) or (AValue.Kind <> TSyntaxKind.Call) then
  begin
    Exit;
  end;
  for mIndex := 1 to AValue.ChildCount - 1 do
  begin
    if (AValue[mIndex].Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
      SameText(AValue[mIndex].Name, 'False') then
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

  /// <summary>Feld der Klasse mit Record-Typ (FSystem: TUpdateSystem).</summary>
  TRecordField = record
    Name: string;
    TypeName: string;
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
    FRecordFields: TArray<TRecordField>;
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
    /// <summary>ANode ist FFeld oder Self.FFeld mit einem Interface-Typ, oder FRecord.Feld mit einem Interface-Typ
    /// in einem Record-Feld (FSystem.Registry: IUpdateRegistry).</summary>
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
  mSection: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mSection := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    mSection := ATree.Root;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if mSection[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + [mSection[mIndex]];
    end;
  end;
end;

/// <summary>Methoden TKlasse.Name mit Rumpf, ohne Methoden verschachtelter Klassen.</summary>
function ClassMethods(ATree: TSyntaxTree; const AClassName: string): TArray<TSyntaxNode>;
var
  mDecl: TSyntaxNode;
  mRest: string;
begin
  Result := nil;
  for mDecl in RoutineDecls(ATree) do
  begin
    if StartsText(AClassName + '.', mDecl.Name) and (mDecl.FindChild(TSyntaxKind.Block) <> nil) then
    begin
      mRest := Copy(mDecl.Name, Length(AClassName) + 2, MaxInt);
      if (mRest <> '') and (Pos('.', mRest) = 0) then
      begin
        Result := Result + [mDecl];
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
  mText: string;
begin
  mText := TrimLeft(AText);
  Result := StartsText(AWord, mText) and ((Length(mText) = Length(AWord)) or
    not CharInSet(mText[Length(AWord) + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

function IsConstructorDecl(const AText: string; ADecl: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
begin
  mHeader := HeaderOf(ADecl);
  Result := (mHeader <> nil) and StartsWithWord(TFreeFieldTypes.NodeText(AText, mHeader), 'constructor');
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
  mRecord: TRecordField;
begin
  mName := SelfMemberName(ANode);
  Result := (mName <> '') and MatchText(mName, FInterfaceFields);
  if Result or (ANode.Kind <> TSyntaxKind.MemberAccess) or (ANode.ChildCount <> 1) then
  begin
    Exit;
  end;
  // Die Referenzzählung des Record-Felds gibt das Objekt frei wie bei einem Interface-Feld (#1519).
  mName := SelfMemberName(ANode[0]);
  for mRecord in FRecordFields do
  begin
    if (mName <> '') and SameText(mRecord.Name, mName) then
    begin
      Result := FTypes.TypeGuess(FTypes.MemberType(mRecord.TypeName, ANode.Name)) = tgInterface;
    end;
  end;
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
  Result := MatchText(TFreeFieldTypes.BaseName(AContainer), cOwningContainers);
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
    FFields[mField].Reason := cOwnedReason;
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
    (FFields[AField].Reason <> cInterfaceReason) and (FFields[AField].Reason <> cOwnedReason) then
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
      if (ANode.ChildCount >= 1) and MatchText(ANode.Name, cFreeMethods) then
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
      SetUnclear(FieldRef(ANode[1]), cTexts[TFreeFieldsText.IsReturnedBy].Fmt([AMethod]));
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
      FFields[mField].Reason := cOwnedReason;
    end
    else
    begin
      SetUnclear(mField, cTexts[TFreeFieldsText.IsPassedTo1In].Fmt([AMethod, TFreeFieldTypes.CodeOf(FText, ANode[0])]));
    end;
  end;
end;

procedure TClassAnalyzer.NoteCopy(ATarget: TSyntaxNode; AField: Integer; const AMethod: string);
var
  mAlias: TFieldAlias;
begin
  if (ATarget.Kind = TSyntaxKind.Identifier) and SameText(ATarget.Name, 'Result') then
  begin
    SetUnclear(AField, cTexts[TFreeFieldsText.IsReturnedBy].Fmt([AMethod]));
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
    SetUnclear(AField, cTexts[TFreeFieldsText.IsPassedTo1In].Fmt([AMethod, TFreeFieldTypes.CodeOf(FText, ATarget)]));
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
    FFields[mField].Reason := cInterfaceReason;
  end
  else if mField >= 0 then
  begin
    NoteCopy(mTarget, mField, AMethod);
  end;
  mField := FieldRef(mTarget);
  if (mField >= 0) and not Creation(ANode[1], mTypeName, mOwned) and not IsNilLiteral(ANode[1]) then
  begin
    SetUnclear(mField, cTexts[TFreeFieldsText.IsAlsoAssignedWithoutCreate].Fmt([AMethod]));
  end;
end;

procedure TClassAnalyzer.ReadField(AChild: TSyntaxNode);
var
  mTypeRef: TSyntaxNode;
  mTypeName, mName: string;
  mGuess: TTypeGuess;
  mRecord: TRecordField;
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
  end
  else if mGuess = tgRecord then
  begin
    for mName in TrimmedNames(AChild.Name) do
    begin
      mRecord.Name := mName;
      mRecord.TypeName := mTypeName;
      FRecordFields := FRecordFields + [mRecord];
    end;
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
      SetUnclear(FieldIndex(mWritten), cTexts[TFreeFieldsText.CanBeSetFromOutside].Fmt([FClassNode[mIndex].Name]));
    end;
  end;
  for mIndex in FCreated do
  begin
    if not mFreed[mIndex] and (FFields[mIndex].Reason <> cOwnedReason) and
      (FFields[mIndex].Reason <> cInterfaceReason) then
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
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mFound = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.StartPos.Line = ALine) and
        SameText(ANode.Name, AClassName) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

function PlaceOf(ATree: TSyntaxTree; const AText: string; ADecl: TSyntaxNode): TDestructorPlace;
var
  mClassNode, mHeader, mDecl: TSyntaxNode;
  mIndex: Integer;
begin
  Result := Default(TDestructorPlace);
  mClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  for mIndex := 0 to mClassNode.ChildCount - 1 do
  begin
    if IsDestructorHeader(AText, mClassNode[mIndex]) and (mClassNode[mIndex].Kind = TSyntaxKind.RoutineHeader) then
    begin
      Result.Declaration := mClassNode[mIndex];
    end;
  end;
  for mDecl in ClassMethods(ATree, ADecl.Name) do
  begin
    mHeader := HeaderOf(mDecl);
    if SameText(mDecl.Name, ADecl.Name + '.Destroy') and (mHeader <> nil) and
      StartsWithWord(TFreeFieldTypes.NodeText(AText, mHeader), 'destructor') then
    begin
      Result.Body := mDecl;
    end
    else if IsConstructorDecl(AText, mDecl) then
    begin
      Result.LastConstructor := mDecl;
    end;
  end;
end;

/// <summary>Klassenname des Rumpfs samt generischer Parameter: "constructor TFoo&lt;T&gt;.Create(…)" →
/// TFoo&lt;T&gt;.</summary>
function Qualifier(const AText: string; AConstructor: TSyntaxNode; const AClassName: string): string;
var
  mHeader: string;
  mStop: Integer;
begin
  // Text vom Anfang der Routine bis zum Block; der Kopfknoten generischer Klassen deckt nicht alles ab.
  mHeader := TFreeFieldTypes.Collapse(Copy(AText, AConstructor.StartOffset + 1,
    AConstructor.FindChild(TSyntaxKind.Block).StartOffset - AConstructor.StartOffset));
  // "constructor" bzw. "class constructor" (#971) abschneiden.
  mHeader := Trim(Copy(mHeader, Pos('constructor', LowerCase(mHeader)) + Length('constructor'), MaxInt));
  mStop := Pos('(', mHeader);
  if mStop = 0 then
  begin
    mStop := Pos(';', mHeader);
  end;
  if mStop > 0 then
  begin
    mHeader := Copy(mHeader, 1, mStop - 1);
  end;
  mStop := LastDelimiter('.', mHeader);
  Result := AClassName;
  if mStop > 1 then
  begin
    Result := Trim(Copy(mHeader, 1, mStop - 1));
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
  mBlock, mChild, mAnchor: TSyntaxNode;
  mIndex: Integer;
  mPosition: TTextPosition;
  mPrefix, mIndent, mText, mStatement: string;
begin
  mBlock := ABody.FindChild(TSyntaxKind.Block);
  mAnchor := nil;
  for mIndex := 0 to mBlock.ChildCount - 1 do
  begin
    mChild := mBlock[mIndex];
    if IsInheritedCall(mChild) then
    begin
      mAnchor := mChild;
      Break;
    end;
  end;
  if mAnchor <> nil then
  begin
    mPosition := mAnchor.StartPos;
    mIndent := '';
  end
  else
  begin
    // "end" des Blocks: drei Zeichen vor dessen Ende.
    mPosition := TTextPosition.Create(mBlock.EndPos.Line, mBlock.EndPos.Character - 3);
    mIndent := '  ';
  end;
  mPrefix := '';
  if mPosition.Line <= High(ALines) then
  begin
    mPrefix := Copy(ALines[mPosition.Line], 1, mPosition.Character);
  end;
  mText := '';
  if Trim(mPrefix) = '' then
  begin
    // Eigene Zeilen vor der Ankerzeile, eingerückt wie sie (bzw. eine Stufe tiefer als "end").
    mIndent := mPrefix + mIndent;
    for mStatement in AStatements do
    begin
      mText := mText + mIndent + mStatement + ALineBreak;
    end;
    Result := InsertAt(TTextPosition.Create(mPosition.Line, 0), mText);
  end
  else
  begin
    for mStatement in AStatements do
    begin
      mText := mText + mStatement + ' ';
    end;
    Result := InsertAt(mPosition, mText);
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
  mDecls: TArray<TSyntaxNode>;
  mDecl: TSyntaxNode;
  mAnalyzer: TClassAnalyzer;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mDecls := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // Klassen in Typabschnitten; verschachtelte Klassen nicht.
      Result := ANode.Kind <> TSyntaxKind.ClassType;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        mDecls := mDecls + [ANode];
      end;
    end);
  for mDecl in mDecls do
  begin
    mAnalyzer := TClassAnalyzer.Create(ATree, AText, AIndex, mDecl);
    try
      Result := Result + mAnalyzer.Fields;
    finally
      mAnalyzer.Free;
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
  mStatements: TArray<string>;
  mOrder: TArray<Integer>;
  mIndex, mOther, mSwap: Integer;
begin
  AEdits := nil;
  Result := False;
  if (ATree = nil) or (Length(AFields) = 0) then
  begin
    Exit;
  end;
  // Umgekehrte Erzeugungsreihenfolge.
  mOrder := nil;
  for mIndex := 0 to High(AFields) do
  begin
    mOrder := mOrder + [mIndex];
  end;
  for mIndex := 0 to High(mOrder) - 1 do
  begin
    for mOther := mIndex + 1 to High(mOrder) do
    begin
      if AFields[mOrder[mOther]].Order > AFields[mOrder[mIndex]].Order then
      begin
        mSwap := mOrder[mIndex];
        mOrder[mIndex] := mOrder[mOther];
        mOrder[mOther] := mSwap;
      end;
    end;
  end;
  mStatements := nil;
  for mIndex in mOrder do
  begin
    mStatements := mStatements + [Statement(AFields[mIndex].Name, AStyle)];
  end;
  Result := DestructorEdits(ATree, AText, AFields[0].ClassName, AFields[0].ClassLine, mStatements, AEdits);
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
  Result.Kind := cQuickFixKind;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.FreeFields', cTexts);

end.
