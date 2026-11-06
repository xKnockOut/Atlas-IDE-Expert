unit Atlas.Common.Editing.NestedRoutines;

// Lokale Routine und Methode ineinander umwandeln (#663):
//   In private Methode umwandeln (auf dem Kopf einer lokalen Routine in einer
//     Methode): Der Rumpf wandert hinter die äußere Methode als TKlasse.Name,
//     die Deklaration in den private-Abschnitt der Klasse (legt ihn an, wenn
//     er fehlt). Variablen, Konstanten und Parameter der äußeren Routine, die
//     die lokale nutzt, werden Parameter: var, wenn sie geschrieben werden
//     (auch als var-Argument), const bei reinem Lesen von Strings, Records
//     und Interfaces, sonst ohne Modifizierer. Untypisierte Konstanten
//     wandern als Konstanten mit. Die Aufrufe bekommen die neuen Argumente,
//     ein vergebener Name bekommt eine Nummer.
//   Aus Routine herauslösen: dasselbe für eine lokale Routine einer freien
//     Routine; sie steht danach vor ihr in der Unit.
//   Als lokale Routine einbetten (auf einer privaten Methode mit genau einem
//     Aufruf, und zwar im Rumpf einer anderen Methode derselben Klasse; nicht
//     virtual, dynamic, override, abstract, message, overload, nicht als
//     Ereignis oder Methodenzeiger benutzt): Der Rumpf wird lokale Routine des
//     Aufrufers, die Deklaration verschwindet aus der Klasse.
//   In lokale Routine umwandeln: dasselbe für eine freie Routine der
//     Implementierung, die nicht im interface steht.
//   Mit „durchgereichte Parameter entfernen“ fallen Parameter weg, denen der
//     Aufruf nur eine Variable oder einen Parameter des Aufrufers übergibt;
//     der Rumpf nutzt dann diese direkt.
// Nicht angeboten wird, wenn sich die Bedeutung eines Namens ändern könnte:
// die lokale Routine nutzt Result, eine andere lokale Routine oder einen
// lokalen Typ der äußeren, enthält with, fängt einen künftigen var-Parameter
// in einer anonymen Methode ein oder wird anders als aufgerufen benutzt; beim
// Einbetten verdeckt ein Name des Aufrufers einen Namen des Rumpfs. Liegt die
// lokale Routine in einer anderen lokalen Routine, gibt es statt der Aktion
// einen Hinweis. Jede Aktion ist ein Rückgängig-Schritt und trägt eine
// Vorschau mit der neuen Signatur und der Zahl der geänderten Aufrufe.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions;

type
  /// <summary>Ist der Typ ATypeName an AOffset ein Record oder Interface (dann const beim reinen Lesen)?</summary>
  TConstTypeFunc = reference to function(const ATypeName: string; AOffset: Integer): Boolean;

  TNestedRoutineLookup = record
    ConstType: TConstTypeFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (var-Argumente schreiben).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Records und Interfaces unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TNestedRoutineLookup; static;
    /// <summary>Typen über AResolver für ATree der Datei AFileName (Baum festhalten, solange gebraucht).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TNestedRoutineLookup; static;
  end;

  /// <summary>Wo und womit eine Umwandlung arbeitet: Quelltext, Baum, Cursorstelle, Typauskunft und Stil.
  /// </summary>
  TNestedRoutineRequest = record
    Text: string;
    Tree: TSyntaxTree;
    Position: TTextPosition;
    Lookup: TNestedRoutineLookup;
    Style: TFormatStyle;
    class function Create(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TNestedRoutineRequest; static;
  end;

  TNestedRoutines = class
  public
    class function ToMethodTitle: string; static;
    class function ToUnitRoutineTitle: string; static;
    class function EmbedMethodTitle: string; static;
    class function EmbedRoutineTitle: string; static;
    class function PassThroughSuffix: string; static;
    /// <summary>„In private Methode umwandeln“ bzw. „Aus Routine herauslösen“ für die lokale Routine, deren Kopf
    /// ARequest.Position enthält. Liegt sie in einer anderen lokalen Routine, ist AAction.Disabled der Hinweis.
    /// </summary>
    class function Extract(const ARequest: TNestedRoutineRequest; out AAction: TCodeAction): Boolean; overload;
      static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Extract(const ARequest: TNestedRoutineRequest; out AAction: TCodeAction;
      out AReason: string): Boolean; overload; static;
    /// <summary>„Als lokale Routine einbetten“ bzw. „In lokale Routine umwandeln“ für die Routine, deren Kopf
    /// (Implementierung oder Klassendeklaration) ARequest.Position enthält; mit ARemovePassThrough ohne die
    /// durchgereichten Parameter (False, wenn es keine gibt).</summary>
    class function Embed(const ARequest: TNestedRoutineRequest; ARemovePassThrough: Boolean;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Embed(const ARequest: TNestedRoutineRequest; ARemovePassThrough: Boolean;
      out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    /// <summary>Alle passenden Aktionen an APosition.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.CreateMethod,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TNestedRoutinesText = (NoTree, NoLocalRoutine, UnsupportedForm, ClassNotInTheFile, ResultOfTheOuterRoutine,
    CallsTheOuterRoutine, UsesTheLocalRoutine, UsesTheLocalType, WritesTheConstant, HasNoType,
    AnAnonymousMethodCaptures, UnsupportedParameters, IsNotOnlyCalled, HeaderNotReadable,
    ClassDeclarationCannotBeExtended, ChangedCalls, LiesInTheLocalRoutine, NoRoutineOfTheImplementation, Overloaded,
    DeclarationMissing, NotPrivate, VirtualMessageOrOverloaded, UsedViaAnotherObject, NotExactlyOneCall,
    NotUsedAsACall, CallerIsNotARoutine, CallerIsNotAMethod, NoParametersPassedThrough, AMemberOfTheClass,
    BeginOfTheCallerIs, ChangedCalls1, RoutineWithoutBody, ANameHides, NewSignature, AlsoDeclaredElsewhere,
    AlreadyKnows, NameResult, NewLocalRoutineIn, Recursive, Hides, ConvertToPrivateMethod, ExtractFromRoutine,
    EmbedAsLocalRoutine, ConvertToLocalRoutine, RemovePassedThroughParameters);

const
  cTexts: array[TNestedRoutinesText] of TAtlasText = (
    (De: 'kein Baum'; En: 'no tree'),
    (De: 'keine lokale Routine'; En: 'no local routine'),
    (De: 'nicht unterstützte Form'; En: 'unsupported form'),
    (De: 'Klasse %s nicht in der Datei'; En: 'Class %s not in the file'),
    (De: 'Result der äußeren Routine'; En: 'Result of the outer routine'),
    (De: 'ruft die äußere Routine auf'; En: 'calls the outer routine'),
    (De: 'nutzt die lokale Routine '; En: 'uses the local routine '),
    (De: 'nutzt den lokalen Typ '; En: 'uses the local type '),
    (De: 'schreibt die Konstante '; En: 'writes the constant '),
    (De: ' hat keinen Typ'; En: ' has no type'),
    (De: 'eine anonyme Methode fängt %s ein'; En: 'an anonymous method captures %s'),
    (De: 'nicht unterstützte Parameter'; En: 'unsupported parameters'),
    (De: ' wird nicht nur aufgerufen'; En: ' is not only called'),
    (De: 'Kopf nicht lesbar'; En: 'header not readable'),
    (De: 'Klassendeklaration nicht erweiterbar'; En: 'class declaration cannot be extended'),
    (De: 'Geänderte Aufrufe: %d'; En: 'Changed calls: %d'),
    (De: '%s liegt in der lokalen Routine %s; erst diese umwandeln';
     En: '%s lies in the local routine %s; convert that one first'),
    (De: 'keine Routine der Implementierung'; En: 'no routine of the implementation'),
    (De: 'überladen'; En: 'overloaded'),
    (De: 'Deklaration fehlt'; En: 'declaration missing'),
    (De: 'nicht privat'; En: 'not private'),
    (De: 'virtuell, Botschaft oder überladen'; En: 'virtual, message or overloaded'),
    (De: 'über ein anderes Objekt benutzt'; En: 'used via another object'),
    (De: 'nicht genau ein Aufruf'; En: 'not exactly one call'),
    (De: 'nicht als Aufruf benutzt'; En: 'not used as a call'),
    (De: 'Aufrufer ist keine Routine der Implementierung'; En: 'caller is not a routine of the implementation'),
    (De: 'Aufrufer ist keine Methode derselben Art'; En: 'caller is not a method of the same kind'),
    (De: 'keine durchgereichten Parameter'; En: 'no parameters passed through'),
    (De: 'ein Mitglied der Klasse verdeckt '; En: 'a member of the class hides '),
    (De: 'begin des Aufrufers steht nicht am Zeilenanfang';
     En: 'begin of the caller is not at the beginning of the line'),
    (De: 'Geänderte Aufrufe: 1'; En: 'Changed calls: 1'),
    (De: 'Routine ohne Rumpf'; En: 'routine without body'),
    (De: 'ein Name verdeckt '; En: 'a name hides '),
    (De: 'Neue Signatur: %s'; En: 'New signature: %s'),
    (De: 'auch anderswo deklariert'; En: 'also declared elsewhere'),
    (De: ' kennt schon '; En: ' already knows '),
    (De: 'Name Result'; En: 'name Result'),
    (De: 'Neue lokale Routine in %s: %s'; En: 'New local routine in %s: %s'),
    (De: 'rekursiv'; En: 'recursive'),
    (De: ' verdeckt '; En: ' hides '),
    (De: 'In private Methode umwandeln'; En: 'Convert to private method'),
    (De: 'Aus Routine herauslösen'; En: 'Extract from routine'),
    (De: 'Als lokale Routine einbetten'; En: 'Embed as local routine'),
    (De: 'In lokale Routine umwandeln'; En: 'Convert to local routine'),
    (De: ' (durchgereichte Parameter entfernen)'; En: ' (remove passed-through parameters)'));

{$SCOPEDENUMS OFF}

class function TNestedRoutines.ToMethodTitle: string;
begin
  Result := cTexts[TNestedRoutinesText.ConvertToPrivateMethod].Text;
end;

class function TNestedRoutines.ToUnitRoutineTitle: string;
begin
  Result := cTexts[TNestedRoutinesText.ExtractFromRoutine].Text;
end;

class function TNestedRoutines.EmbedMethodTitle: string;
begin
  Result := cTexts[TNestedRoutinesText.EmbedAsLocalRoutine].Text;
end;

class function TNestedRoutines.EmbedRoutineTitle: string;
begin
  Result := cTexts[TNestedRoutinesText.ConvertToLocalRoutine].Text;
end;

class function TNestedRoutines.PassThroughSuffix: string;
begin
  Result := cTexts[TNestedRoutinesText.RemovePassedThroughParameters].Text;
end;

type
  /// <summary>Name der äußeren Routine, den die lokale nutzt.</summary>
  TCaptured = record
    Local: TRoutineLocal;
    Written: Boolean;
    /// <summary>In einer anonymen Methode benutzt (darf kein var-Parameter werden).</summary>
    InAnonymous: Boolean;
  end;

{ Hilfen }

{ TNestedRoutineLookup }

class function TNestedRoutineLookup.FromTree(ATree: TSyntaxTree): TNestedRoutineLookup;
begin
  Result.ConstType := nil;
  Result.Flow := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
  end;
end;

class function TNestedRoutineLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TNestedRoutineLookup;
var
  FileName: string;
begin
  Result := FromTree(ATree);
  FileName := AFileName;
  Result.ConstType :=
    function(const ATypeName: string; AOffset: Integer): Boolean
    var
      Resolved: TResolvedSymbol;
      Base: string;
    begin
      Base := ATypeName;
      if Pos('<', Base) > 0 then
      begin
        Base := Copy(Base, 1, Pos('<', Base) - 1);
      end;
      Resolved := AResolver.ResolveChain(ATree, FileName, Trim(Base).Split(['.']), AOffset);
      Result := Resolved.Found and Resolved.IsType and (Resolved.SymbolKind in [TIndexSymbolKind.RecordType,
        TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
    end;
end;

{ Umwandlung: lokale Routine heraus }

/// <summary>Modifizierer des neuen Parameters für den Namen ACaptured.</summary>
function ModeOf(const ACaptured: TCaptured; const ALookup: TNestedRoutineLookup; AOffset: Integer): string;
begin
  Result := '';
  if ACaptured.Written then
  begin
    Result := 'var';
  end
  else if TCreateMethod.WantsConst(ACaptured.Local.TypeText, False, False) or
    (Assigned(ALookup.ConstType) and ALookup.ConstType(ACaptured.Local.TypeText, AOffset)) then
  begin
    Result := 'const';
  end;
end;

/// <summary>Bearbeitung für den Aufruf ACall mit Klammern; False, wenn die schließende Klammer nicht zu finden ist.
/// </summary>
function ParenthesizedCallEdit(const ATokens: TArray<TPascalToken>; ANode, ACall: TSyntaxNode;
  const ANewName, AArguments: string; var AEdits: TArray<TOffsetEdit>): Boolean;
var
  mClose: Integer;
begin
  Result := True;
  if not SameText(ANode.Name, ANewName) then
  begin
    AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
  end;
  if AArguments = '' then
  begin
    Exit;
  end;
  if ACall.ChildCount > 1 then
  begin
    AEdits := AEdits + [TOffsetEdit.Create(ACall[ACall.ChildCount - 1].EndOffset,
      ACall[ACall.ChildCount - 1].EndOffset, ', ' + AArguments)];
  end
  else
  begin
    mClose := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, ACall.EndOffset));
    Result := (mClose >= 0) and ATokens[mClose].IsSymbol(')');
    if Result then
    begin
      AEdits := AEdits + [TOffsetEdit.Create(ATokens[mClose].Offset, ATokens[mClose].Offset, AArguments)];
    end;
  end;
end;

/// <summary>Darf der Bezeichner ANode ohne Klammern unter AParent ein Aufruf sein? Als Anweisung, bei Funktionen
/// auch in Ausdrücken; nicht als Wert (@X, Argument, Ziel einer Zuweisung).</summary>
function IsBareCall(ANode, AParent: TSyntaxNode; AIsFunction: Boolean): Boolean;
begin
  if (AParent = nil) or (AParent.Kind in [TSyntaxKind.AddressOf, TSyntaxKind.Call, TSyntaxKind.MemberAccess]) then
  begin
    Exit(False);
  end;
  if AParent.Kind = TSyntaxKind.AssignStatement then
  begin
    Exit(AIsFunction and (AParent[0] <> ANode));
  end;
  Result := (AParent.Kind = TSyntaxKind.CallStatement) or AIsFunction;
end;

/// <summary>Bearbeitung, die AArguments an den Aufruf des Bezeichners ANode anhängt bzw. ihn in ANewName
/// umbenennt; False, wenn die Routine dort nicht aufgerufen, sondern anders benutzt wird.</summary>
function CallEdit(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; AIsFunction: Boolean;
  const ANewName, AArguments: string; var AEdits: TArray<TOffsetEdit>): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  if (mParent <> nil) and (mParent.Kind = TSyntaxKind.Call) and (mParent[0] = ANode) then
  begin
    Exit(ParenthesizedCallEdit(ATokens, ANode, mParent, ANewName, AArguments, AEdits));
  end;
  Result := IsBareCall(ANode, mParent, AIsFunction);
  if not Result then
  begin
    Exit;
  end;
  if AArguments <> '' then
  begin
    AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName + '(' + AArguments + ')')];
  end
  else if not SameText(ANode.Name, ANewName) then
  begin
    AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
  end;
end;

/// <summary>Kommt ein Bezeichner AName unter AIdentifiers vor?</summary>
function UsesName(const AIdentifiers: TArray<TSyntaxNode>; const AName: string): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
  begin
    if SameText(Node.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Schreibt der Rumpf von ARoutine den eigenen Namen AName (Zuweisung, var-Argument, @)?</summary>
function WritesName(ACache: TLocalsCache; const AIdentifiers: TArray<TSyntaxNode>; ARoutine: TSyntaxNode;
  const AName: string; const AFlow: TFlowSignatureLookup): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
  begin
    if SameText(Node.Name, AName) and not TRoutineParts.Shadowed(ACache, Node, ARoutine, AName, False) and
      (TRoutineLocals.AccessOf(Node, AFlow) <> TLocalAccess.Read) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Bezeichner der Art AKind unter ANode in Quelltextreihenfolge.</summary>
function Collected(ANode: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mList: TList<TSyntaxNode>;
begin
  mList := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, AKind, mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Hat der Kopf AHeader Parameter, die ParameterTexts nicht lesen konnte?</summary>
function UnreadableParameters(AHeader: TSyntaxNode; const AParameters: TArray<TParameterText>): Boolean;
var
  mParameters: TSyntaxNode;
begin
  mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
  Result := (AParameters = nil) and (mParameters <> nil) and (mParameters.ChildCount > 0);
end;

/// <summary>Bearbeitungen AEdits als Textbearbeitungen über ALines.</summary>
function TextEdits(const ALines: TLineTable; const AEdits: TArray<TOffsetEdit>): TArray<TTextEdit>;
var
  mEdit: TOffsetEdit;
begin
  Result := nil;
  for mEdit in AEdits do
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(ALines.PositionAt(mEdit.Start),
      ALines.PositionAt(mEdit.Stop)), mEdit.Text)];
  end;
end;

type
  /// <summary>Arbeitsstand von „In private Methode umwandeln“ bzw. „Aus Routine herauslösen“: die lokale Routine
  /// Inner der Routine Outer, die Namen Captured der äußeren, die sie nutzt, die neuen Parameter und Argumente und
  /// die Bearbeitungen in der lokalen (InnerEdits) und der äußeren Routine (OuterEdits).</summary>
  TExtraction = record
    Request: TNestedRoutineRequest;
    Lines: TLineTable;
    Tokens: TArray<TPascalToken>;
    Inner: TSyntaxNode;
    Outer: TSyntaxNode;
    Header: TSyntaxNode;
    TypeBody: TSyntaxNode;
    QualifiedClass: string;
    IsMethod: Boolean;
    IsClass: Boolean;
    InnerIsFunction: Boolean;
    LineBreak: string;
    InnerIndent: string;
    Cache: TLocalsCache;
    OuterLocals: TArray<TRoutineLocal>;
    Captured: TArray<TCaptured>;
    Parameters: TArray<TParameterText>;
    Arguments: string;
    ConstLines: string;
    NewName: string;
    QualifiedName: string;
    Declaration: string;
    Calls: Integer;
    InnerEdits: TArray<TOffsetEdit>;
    OuterEdits: TArray<TOffsetEdit>;
    /// <summary>Lokale Routine mit Kopf an APosition und ihre äußere Routine.</summary>
    function LocateIssue(const APosition: TTextPosition): string;
    /// <summary>Liegt die äußere Routine selbst in einer Routine?</summary>
    function InNested: Boolean;
    function Title: string;
    /// <summary>Rumpf, Modifizierer, with und Klasse in der Datei.</summary>
    function FormIssue: string;
    /// <summary>Verbietet der Name ANode die Umwandlung (Result der äußeren Funktion, Aufruf der äußeren)?
    /// </summary>
    function NameIssue(ANode: TSyntaxNode): string;
    /// <summary>Darf die lokale Routine die äußere Lokale ALocal sehen (Parameter oder davor deklariert)?</summary>
    function IsVisible(const ALocal: TRoutineLocal): Boolean;
    /// <summary>Index der äußeren Lokalen zum Bezeichner ANode; -1 ohne.</summary>
    function OuterLocalOf(ANode: TSyntaxNode): Integer;
    /// <summary>Nutzt ANode eine andere lokale Routine oder einen lokalen Typ der äußeren?</summary>
    function OuterDeclarationIssue(ANode: TSyntaxNode): string;
    /// <summary>Merkt die äußere Lokale AFound als genutzt durch ANode.</summary>
    procedure Capture(ANode: TSyntaxNode; AFound: Integer);
    /// <summary>Namen der lokalen Routine, die die äußere deklariert.</summary>
    function CaptureIssue: string;
    /// <summary>Lokale Typen der äußeren Routine auch in Typangaben.</summary>
    function TypeIssue: string;
    function AddConstant(const ACaptured: TCaptured): string;
    function AddParameter(const ACaptured: TCaptured): string;
    /// <summary>Neue Parameter; untypisierte Konstanten wandern als Konstanten mit.</summary>
    function ParameterIssue: string;
    function CallIssue(ANode: TSyntaxNode; var AEdits: TArray<TOffsetEdit>): string;
    /// <summary>Rekursion: Ein innerer Name verdeckt die Routine oder ein neues Argument.</summary>
    function RecursiveCallIssue(ANode: TSyntaxNode): string;
    /// <summary>Verdeckt eine Inline- oder Schleifenvariable gleichen Namens die Routine bei ANode?</summary>
    function ShadowedByLocal(ANode: TSyntaxNode): Boolean;
    /// <summary>Meint der Name des neuen Arguments ACaptured bei ANode etwas anderes?</summary>
    function ArgumentShadowed(ANode: TSyntaxNode; const ACaptured: TCaptured): Boolean;
    function OuterCallIssue(ANode: TSyntaxNode): string;
    /// <summary>Aufrufe in der äußeren Routine (auch in den anderen lokalen Routinen) und in der lokalen selbst.
    /// </summary>
    function CallsIssue: string;
    /// <summary>Hat die äußere Klassenmethode static? Dann hat auch die neue kein Self.</summary>
    function OuterIsStatic: Boolean;
    /// <summary>Kopf und Deklaration der neuen Routine.</summary>
    function HeadIssue: string;
    /// <summary>Text: ganze Zeilen samt Kommentaren darüber, eingerückt wie die äußere Routine.</summary>
    function MovedText: string;
    /// <summary>Entfernen, mit einer der Leerzeilen um die Routine; folgt dann begin, auch die Leerzeile davor.
    /// </summary>
    function RemovalEdit: TTextEdit;
    function EditsIssue(var AAction: TCodeAction): string;
    function Run(var AAction: TCodeAction): string;
  end;

function TExtraction.LocateIssue(const APosition: TTextPosition): string;
begin
  if (Request.Tree = nil) or (Request.Tree.Root = nil) then
  begin
    Exit(cTexts[TNestedRoutinesText.NoTree].Text);
  end;
  Lines := TLineTable.Build(Request.Text);
  Inner := TRoutineParts.RoutineWithHeaderAt(Request.Tree, Lines.OffsetAt(APosition));
  if (Inner = nil) or (Inner.Parent = nil) or (Inner.Parent.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Exit(cTexts[TNestedRoutinesText.NoLocalRoutine].Text);
  end;
  Outer := Inner.Parent;
  QualifiedClass := TRoutineBody.QualifierOf(Outer.Name);
  IsMethod := QualifiedClass <> '';
  Result := '';
end;

function TExtraction.InNested: Boolean;
begin
  Result := (Outer.Parent <> nil) and (Outer.Parent.Kind = TSyntaxKind.RoutineDecl);
end;

function TExtraction.Title: string;
begin
  if IsMethod then
  begin
    Result := TNestedRoutines.ToMethodTitle;
  end
  else
  begin
    Result := TNestedRoutines.ToUnitRoutineTitle;
  end;
end;

function TExtraction.FormIssue: string;
var
  mOuterHeader: TSyntaxNode;
begin
  Tokens := Request.Tree.Tokens;
  Header := TRoutineParts.HeaderOf(Inner);
  mOuterHeader := TRoutineParts.HeaderOf(Outer);
  if (Header = nil) or (mOuterHeader = nil) or (TRoutineBody.BodyOf(Inner) = nil) then
  begin
    Exit(cTexts[TNestedRoutinesText.RoutineWithoutBody].Text);
  end;
  if TRoutineParts.HasWord(Tokens, Header, ['forward', 'external', 'overload', 'assembler']) or
    TRoutineLocals.HasKind(Inner, TSyntaxKind.WithStatement) or (Pos('<', QualifiedClass) > 0) then
  begin
    Exit(cTexts[TNestedRoutinesText.UnsupportedForm].Text);
  end;
  IsClass := TRoutineParts.IsClassHeader(Tokens, mOuterHeader);
  InnerIsFunction := TRoutineParts.IsFunction(Inner);
  LineBreak := TTextLines.LineBreakOf(Request.Text);
  InnerIndent := TTextLines.IndentOf(Request.Text, Inner.StartPos.Line);
  TypeBody := nil;
  Result := '';
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(Request.Tree.Root, TRoutineBody.ShortNameOf(QualifiedClass));
    if TypeBody = nil then
    begin
      Result := cTexts[TNestedRoutinesText.ClassNotInTheFile].Fmt([QualifiedClass]);
    end;
  end;
end;

function TExtraction.NameIssue(ANode: TSyntaxNode): string;
begin
  Result := '';
  if SameText(ANode.Name, 'Result') and TRoutineParts.IsFunction(Outer) then
  begin
    Result := cTexts[TNestedRoutinesText.ResultOfTheOuterRoutine].Text;
  end
  else if not IsMethod and SameText(ANode.Name, Outer.Name) then
  begin
    Result := cTexts[TNestedRoutinesText.CallsTheOuterRoutine].Text;
  end;
end;

function TExtraction.IsVisible(const ALocal: TRoutineLocal): Boolean;
begin
  Result := (ALocal.Kind = TRoutineLocalKind.Parameter) or ((ALocal.Kind in [TRoutineLocalKind.Variable,
    TRoutineLocalKind.Constant]) and (ALocal.Decl.StartOffset < Inner.StartOffset));
end;

function TExtraction.OuterLocalOf(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(OuterLocals) do
  begin
    if SameText(OuterLocals[mIndex].Name, ANode.Name) and IsVisible(OuterLocals[mIndex]) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TExtraction.OuterDeclarationIssue(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := 0 to Outer.ChildCount - 1 do
  begin
    mChild := Outer[mIndex];
    if (mChild = Inner) or (mChild.StartOffset >= Inner.StartOffset) then
    begin
      Continue;
    end;
    if (mChild.Kind = TSyntaxKind.RoutineDecl) and SameText(mChild.Name, ANode.Name) then
    begin
      Exit(cTexts[TNestedRoutinesText.UsesTheLocalRoutine].Text + mChild.Name);
    end;
    if (mChild.Kind = TSyntaxKind.TypeSection) and (IndexText(ANode.Name, TRoutineParts.ChildNames(mChild)) >= 0) then
    begin
      Exit(cTexts[TNestedRoutinesText.UsesTheLocalType].Text + ANode.Name);
    end;
  end;
  Result := '';
end;

procedure TExtraction.Capture(ANode: TSyntaxNode; AFound: Integer);
var
  mIndex: Integer;
  mCaptured: TCaptured;
begin
  mIndex := 0;
  while (mIndex <= High(Captured)) and not SameText(Captured[mIndex].Local.Name, OuterLocals[AFound].Name) do
  begin
    Inc(mIndex);
  end;
  if mIndex > High(Captured) then
  begin
    mCaptured := Default(TCaptured);
    mCaptured.Local := OuterLocals[AFound];
    Captured := Captured + [mCaptured];
  end;
  if TRoutineLocals.AccessOf(ANode, Request.Lookup.Flow) <> TLocalAccess.Read then
  begin
    Captured[mIndex].Written := True;
  end;
  if TRoutineParts.InAnonymous(ANode, Inner) then
  begin
    Captured[mIndex].InAnonymous := True;
  end;
end;

function TExtraction.CaptureIssue: string;
var
  mNode: TSyntaxNode;
  mFound: Integer;
begin
  Result := '';
  OuterLocals := Cache.Locals(Outer);
  Captured := nil;
  for mNode in Collected(Inner, TSyntaxKind.Identifier) do
  begin
    if TRoutineParts.Shadowed(Cache, mNode, Inner, mNode.Name, True) or SameText(mNode.Name, Inner.Name) then
    begin
      Continue;
    end;
    Result := NameIssue(mNode);
    mFound := OuterLocalOf(mNode);
    if (Result = '') and (mFound < 0) then
    begin
      Result := OuterDeclarationIssue(mNode);
    end
    else if Result = '' then
    begin
      Capture(mNode, mFound);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

function TExtraction.TypeIssue: string;
var
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  for mNode in Collected(Inner, TSyntaxKind.TypeReference) do
  begin
    for mIndex := 0 to Outer.ChildCount - 1 do
    begin
      mChild := Outer[mIndex];
      if (mChild.Kind = TSyntaxKind.TypeSection) and (IndexText(mNode.Name, TRoutineParts.ChildNames(mChild)) >= 0) and
        not TRoutineParts.Shadowed(Cache, mNode, Inner, mNode.Name, True) then
      begin
        Exit(cTexts[TNestedRoutinesText.UsesTheLocalType].Text + mNode.Name);
      end;
    end;
  end;
  Result := '';
end;

function TExtraction.AddConstant(const ACaptured: TCaptured): string;
begin
  if ACaptured.Written then
  begin
    Exit(cTexts[TNestedRoutinesText.WritesTheConstant].Text + ACaptured.Local.Name);
  end;
  if ConstLines = '' then
  begin
    ConstLines := LineBreak + InnerIndent + 'const';
  end;
  ConstLines := ConstLines + LineBreak + InnerIndent + TRoutineBody.IndentUnit(Request.Style) +
    TRoutineBody.TextOf(Request.Text, ACaptured.Local.Decl);
  Result := '';
end;

function TExtraction.AddParameter(const ACaptured: TCaptured): string;
var
  mParameter: TParameterText;
begin
  if ACaptured.Local.TypeText = '' then
  begin
    Exit(ACaptured.Local.Name + cTexts[TNestedRoutinesText.HasNoType].Text);
  end;
  mParameter := Default(TParameterText);
  mParameter.Modifier := ModeOf(ACaptured, Request.Lookup, Inner.StartOffset);
  if (mParameter.Modifier = 'var') and ACaptured.InAnonymous then
  begin
    Exit(cTexts[TNestedRoutinesText.AnAnonymousMethodCaptures].Fmt([ACaptured.Local.Name]));
  end;
  mParameter.Name := ACaptured.Local.Name;
  mParameter.Rest := ': ' + ACaptured.Local.TypeText;
  Parameters := Parameters + [mParameter];
  if Arguments <> '' then
  begin
    Arguments := Arguments + ', ';
  end;
  Arguments := Arguments + ACaptured.Local.Name;
  Result := '';
end;

function TExtraction.ParameterIssue: string;
var
  mCaptured: TCaptured;
begin
  Parameters := TRoutineParts.ParameterTexts(Request.Text, Header);
  if UnreadableParameters(Header, Parameters) then
  begin
    Exit(cTexts[TNestedRoutinesText.UnsupportedParameters].Text);
  end;
  Arguments := '';
  ConstLines := '';
  Result := '';
  for mCaptured in Captured do
  begin
    if mCaptured.Local.Kind = TRoutineLocalKind.Constant then
    begin
      Result := AddConstant(mCaptured);
    end
    else
    begin
      Result := AddParameter(mCaptured);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

function TExtraction.CallIssue(ANode: TSyntaxNode; var AEdits: TArray<TOffsetEdit>): string;
begin
  Result := '';
  if not CallEdit(Tokens, ANode, InnerIsFunction, NewName, Arguments, AEdits) then
  begin
    Result := Inner.Name + cTexts[TNestedRoutinesText.IsNotOnlyCalled].Text;
  end;
end;

function TExtraction.RecursiveCallIssue(ANode: TSyntaxNode): string;
var
  mCaptured: TCaptured;
begin
  if TRoutineParts.Shadowed(Cache, ANode, Inner, ANode.Name, True) then
  begin
    Exit('');
  end;
  for mCaptured in Captured do
  begin
    if TRoutineParts.Shadowed(Cache, ANode, Inner, mCaptured.Local.Name, False) then
    begin
      Exit(cTexts[TNestedRoutinesText.ANameHides].Text + mCaptured.Local.Name);
    end;
  end;
  Result := CallIssue(ANode, InnerEdits);
end;

function TExtraction.ShadowedByLocal(ANode: TSyntaxNode): Boolean;
var
  mFound: Integer;
begin
  mFound := TRoutineLocals.IndexOf(OuterLocals, ANode.Name, ANode.StartOffset);
  Result := (mFound >= 0) and (OuterLocals[mFound].Kind in [TRoutineLocalKind.InlineVariable,
    TRoutineLocalKind.LoopVariable]);
end;

function TExtraction.ArgumentShadowed(ANode: TSyntaxNode; const ACaptured: TCaptured): Boolean;
var
  mFound: Integer;
begin
  if TRoutineParts.Shadowed(Cache, ANode, Outer, ACaptured.Local.Name, False) then
  begin
    Exit(True);
  end;
  mFound := TRoutineLocals.IndexOf(OuterLocals, ACaptured.Local.Name, ANode.StartOffset);
  Result := (mFound >= 0) and (OuterLocals[mFound].Decl <> ACaptured.Local.Decl);
end;

function TExtraction.OuterCallIssue(ANode: TSyntaxNode): string;
var
  mCaptured: TCaptured;
begin
  if TRoutineParts.Shadowed(Cache, ANode, Outer, ANode.Name, False) or ShadowedByLocal(ANode) then
  begin
    Exit('');
  end;
  for mCaptured in Captured do
  begin
    if ArgumentShadowed(ANode, mCaptured) then
    begin
      Exit(cTexts[TNestedRoutinesText.ANameHides].Text + mCaptured.Local.Name);
    end;
  end;
  Result := CallIssue(ANode, OuterEdits);
  if Result = '' then
  begin
    Inc(Calls);
  end;
end;

function TExtraction.CallsIssue: string;
var
  mNode: TSyntaxNode;
begin
  Calls := 0;
  InnerEdits := nil;
  OuterEdits := nil;
  Result := '';
  for mNode in Collected(Outer, TSyntaxKind.Identifier) do
  begin
    if not SameText(mNode.Name, Inner.Name) then
    begin
      Continue;
    end;
    if TRoutineBody.Within(mNode, Inner) then
    begin
      Result := RecursiveCallIssue(mNode);
    end
    else
    begin
      Result := OuterCallIssue(mNode);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

function TExtraction.OuterIsStatic: Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := 0 to TypeBody.ChildCount - 1 do
  begin
    mChild := TypeBody[mIndex];
    if (mChild.Kind = TSyntaxKind.RoutineHeader) and SameText(mChild.Name, TRoutineBody.ShortNameOf(Outer.Name)) and
      TRoutineParts.HasWord(Tokens, mChild, ['static']) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TExtraction.HeadIssue: string;
var
  mNameFirst, mNameLast: Integer;
begin
  if not TRoutineParts.NameTokens(Tokens, Header, mNameFirst, mNameLast) then
  begin
    Exit(cTexts[TNestedRoutinesText.HeaderNotReadable].Text);
  end;
  QualifiedName := NewName;
  if IsMethod then
  begin
    QualifiedName := QualifiedClass + '.' + NewName;
  end;
  InnerEdits := InnerEdits + [TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
    TRoutineParts.HeadText(Request.Text, Header, QualifiedName, Parameters, IsClass) + ConstLines)];
  Declaration := TRoutineParts.HeadText(Request.Text, Header, NewName, Parameters, IsClass);
  // Eine statische Klassenmethode hat kein Self: die neue auch nicht.
  if IsClass and OuterIsStatic then
  begin
    Declaration := Declaration + ' static;';
  end;
  Result := '';
end;

function TExtraction.MovedText: string;
var
  mStart: Integer;
begin
  mStart := Lines.OffsetAt(TTextPosition.Create(TRoutineBody.RoutineInsertLine(Request.Text, Inner), 0));
  Result := TRoutineParts.ApplyEdits(Copy(Request.Text, mStart + 1, Inner.EndOffset - mStart), mStart, InnerEdits);
  Result := TRoutineBody.Reindent(TrimLeft(Result), InnerIndent, TTextLines.IndentOf(Request.Text,
    Outer.StartPos.Line), LineBreak);
end;

function TExtraction.RemovalEdit: TTextEdit;
var
  mTextLines: TArray<string>;
  mStart, mEnd: Integer;
begin
  mTextLines := TTextLines.SplitLines(Request.Text);
  mStart := TRoutineBody.RoutineInsertLine(Request.Text, Inner);
  mEnd := Inner.EndPos.Line + 1;
  if TRoutineParts.LineIsBlank(mTextLines, mStart - 1) and TRoutineParts.LineIsBlank(mTextLines, mEnd) then
  begin
    Inc(mEnd);
  end;
  if TRoutineParts.LineIsBlank(mTextLines, mStart - 1) and (mEnd = TRoutineBody.BodyOf(Outer).StartPos.Line) then
  begin
    Dec(mStart);
  end;
  Result := TTextEdit.Create(TTextRange.Create(mStart, 0, mEnd, 0), '');
end;

function TExtraction.EditsIssue(var AAction: TCodeAction): string;
var
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
  mMoved: string;
  mInsertLine: Integer;
begin
  mMoved := MovedText;
  mEdits := TArray<TTextEdit>.Create(RemovalEdit) + TextEdits(Lines, OuterEdits);
  if IsMethod then
  begin
    mInsertLine := Outer.EndPos.Line + 1;
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0),
      LineBreak + mMoved + LineBreak)];
    if not TRoutineBody.MemberDeclaration(Request.Text, Request.Tree, TypeBody,
      TMemberEntry.Create('private', Declaration), Request.Style, mEdit) then
    begin
      Exit(cTexts[TNestedRoutinesText.ClassDeclarationCannotBeExtended].Text);
    end;
    mEdits := mEdits + [mEdit];
  end
  else
  begin
    mInsertLine := TRoutineBody.RoutineInsertLine(Request.Text, Outer);
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0),
      mMoved + LineBreak + LineBreak)];
  end;
  AAction.Edits := mEdits;
  AAction.Preview := cTexts[TNestedRoutinesText.NewSignature].Fmt([TRoutineParts.HeadText(Request.Text, Header,
    QualifiedName,
    Parameters, IsClass)]) + LineBreak + cTexts[TNestedRoutinesText.ChangedCalls].Fmt([Calls]);
  Result := '';
end;

function TExtraction.Run(var AAction: TCodeAction): string;
begin
  Result := CaptureIssue;
  if Result = '' then
  begin
    Result := TypeIssue;
  end;
  if Result = '' then
  begin
    Result := ParameterIssue;
  end;
  if Result = '' then
  begin
    // Freier Name.
    if IsMethod then
    begin
      NewName := TRoutineParts.FreeName(Inner.Name, TRoutineBody.MemberNames(TypeBody));
    end
    else
    begin
      NewName := TRoutineParts.FreeName(Inner.Name, TRoutineParts.UnitNames(Request.Tree.Root));
    end;
    Result := CallsIssue;
  end;
  if Result = '' then
  begin
    Result := HeadIssue;
  end;
  if Result = '' then
  begin
    Result := EditsIssue(AAction);
  end;
end;

function ExtractCore(const ARequest: TNestedRoutineRequest; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mWork: TExtraction;
begin
  AAction := Default(TCodeAction);
  mWork := Default(TExtraction);
  mWork.Request := ARequest;
  AReason := mWork.LocateIssue(ARequest.Position);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  AAction.Title := mWork.Title;
  AAction.Kind := RewriteKind;
  if mWork.InNested then
  begin
    // Hinweis statt Aktion: Die mittlere Routine müsste erst selbst heraus.
    AAction.Disabled := cTexts[TNestedRoutinesText.LiesInTheLocalRoutine].Fmt([mWork.Inner.Name,
      mWork.Outer.Name]);
    Exit(True);
  end;
  AReason := mWork.FormIssue;
  if AReason = '' then
  begin
    mWork.Cache := TLocalsCache.Create(ARequest.Text, ARequest.Tree);
    try
      AReason := mWork.Run(AAction);
    finally
      mWork.Cache.Free;
    end;
  end;
  Result := AReason = '';
end;

{ Umwandlung: Routine hinein }

type
  /// <summary>Arbeitsstand von „Als lokale Routine einbetten“ bzw. „In lokale Routine umwandeln“: die Routine
  /// Routine (Deklaration Declaration in der Klasse), ihr einziger Bezug Reference im Rumpf von Caller, die
  /// Argumente des Aufrufs Call und die durchgereichten Parameter (Removed, Renamed: Parameter → Name des
  /// Aufrufers).</summary>
  TEmbedding = record
    Request: TNestedRoutineRequest;
    RemovePassThrough: Boolean;
    Lines: TLineTable;
    Tokens: TArray<TPascalToken>;
    Routine: TSyntaxNode;
    Declaration: TSyntaxNode;
    Header: TSyntaxNode;
    TypeBody: TSyntaxNode;
    Short: string;
    QualifiedClass: string;
    IsMethod: Boolean;
    IsClass: Boolean;
    Cache: TLocalsCache;
    Renamed: TDictionary<string, string>;
    Reference: TSyntaxNode;
    Recursive: Boolean;
    Caller: TSyntaxNode;
    CallerBody: TSyntaxNode;
    Call: TSyntaxNode;
    Arguments: TArray<TSyntaxNode>;
    Parameters: TArray<TParameterText>;
    Removed: TArray<Boolean>;
    Identifiers: TArray<TSyntaxNode>;
    CallerLocals: TArray<TRoutineLocal>;
    LineBreak: string;
    /// <summary>Routine der Implementierung mit Kopf an APosition.</summary>
    function LocateIssue(const APosition: TTextPosition): string;
    /// <summary>Die einzige Deklaration der Methode in der Klasse; sonst der Grund.</summary>
    function FindDeclaration: string;
    /// <summary>Private, nicht virtuelle Methode einer Klasse der Datei.</summary>
    function MethodDeclarationIssue: string;
    /// <summary>Deklariert ASection die Routine noch einmal?</summary>
    function DeclaredIn(ASection: TSyntaxNode): Boolean;
    /// <summary>Im interface oder vorab deklariert: von außen bzw. vor der Implementierung sichtbar.</summary>
    function UnitDeclarationIssue: string;
    function DeclarationIssue: string;
    /// <summary>Self.Name innerhalb einer Methode?</summary>
    function IsSelfAccess(ANode: TSyntaxNode): Boolean;
    /// <summary>Bezüge: genau ein Aufruf außerhalb der Routine.</summary>
    function ReferenceIssue: string;
    /// <summary>Nur Aufrufe, kein Methodenzeiger oder Ereignis.</summary>
    function UsageIssue: string;
    /// <summary>Aufrufer: Routine bzw. Methode derselben Art in der Implementierung.</summary>
    function CallerIssue: string;
    /// <summary>Schreibt der Rumpf den Parameter AIndex, der dann kein var ist?</summary>
    function ParameterWritten(AIndex: Integer): Boolean;
    /// <summary>Meint ATarget im Rumpf schon etwas anderes?</summary>
    function TargetTaken(AIndex: Integer; const ATarget: string): Boolean;
    /// <summary>Argument AIndex ist eine Variable oder ein Parameter des Aufrufers mit demselben Typ; ATarget ist
    /// ihr Name.</summary>
    function IsPassThrough(AIndex: Integer; out ATarget: string): Boolean;
    function PassThroughIssue: string;
    function ParametersIssue: string;
    /// <summary>Lokale Namen der Klasse des Aufrufers, wenn eine freie Routine in eine Methode wandert.</summary>
    function CallerMembers: TArray<string>;
    function BodyNameIssue(ANode: TSyntaxNode; const AMembers: TArray<string>): string;
    /// <summary>Typangaben samt Kopf: ein lokaler Typ des Aufrufers verdeckte sie.</summary>
    function TypeShadowIssue: string;
    /// <summary>Namen des Rumpfs, die der Aufrufer anders belegt, änderten ihre Bedeutung.</summary>
    function ShadowIssue: string;
    function KeptParameters: TArray<TParameterText>;
    /// <summary>Rumpf: Kopf ohne Klasse, durchgereichte Parameter durch die Namen des Aufrufers ersetzt.</summary>
    function BodyEdits(const AKept: TArray<TParameterText>): TArray<TOffsetEdit>;
    function MovedText(const AKept: TArray<TParameterText>): string;
    function RemovalEdits: TArray<TTextEdit>;
    function InsertEdit(const AMoved: string; ABeginLine: Integer): TTextEdit;
    function ArgumentText: string;
    /// <summary>Aufruf: Self. entfällt, durchgereichte Argumente auch.</summary>
    function CallEdits: TArray<TTextEdit>;
    function Title: string;
    function BuildIssue(var AAction: TCodeAction): string;
    function Run(var AAction: TCodeAction): string;
  end;

function TEmbedding.LocateIssue(const APosition: TTextPosition): string;
begin
  if (Request.Tree = nil) or (Request.Tree.Root = nil) then
  begin
    Exit(cTexts[TNestedRoutinesText.NoTree].Text);
  end;
  Lines := TLineTable.Build(Request.Text);
  Tokens := Request.Tree.Tokens;
  Routine := TRoutineParts.TopRoutineAt(Request.Tree, Lines.OffsetAt(APosition), Declaration);
  if (Routine = nil) or (Routine.Parent = nil) or (Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
  begin
    Exit(cTexts[TNestedRoutinesText.NoRoutineOfTheImplementation].Text);
  end;
  Header := TRoutineParts.HeaderOf(Routine);
  if (Header = nil) or (TRoutineBody.BodyOf(Routine) = nil) then
  begin
    Exit(cTexts[TNestedRoutinesText.RoutineWithoutBody].Text);
  end;
  Short := TRoutineBody.ShortNameOf(Routine.Name);
  QualifiedClass := TRoutineBody.QualifierOf(Routine.Name);
  IsMethod := QualifiedClass <> '';
  IsClass := TRoutineParts.IsClassHeader(Tokens, Header);
  Result := '';
  if TRoutineParts.HasWord(Tokens, Header, ['overload', 'forward', 'external', 'export', 'assembler']) or
    (Pos('<', QualifiedClass) > 0) or (Pos('.', QualifiedClass) > 0) then
  begin
    Result := cTexts[TNestedRoutinesText.UnsupportedForm].Text;
  end;
end;

function TEmbedding.FindDeclaration: string;
var
  mIndex: Integer;
begin
  Declaration := nil;
  for mIndex := 0 to TypeBody.ChildCount - 1 do
  begin
    if (TypeBody[mIndex].Kind <> TSyntaxKind.RoutineHeader) or not SameText(TypeBody[mIndex].Name, Short) then
    begin
      Continue;
    end;
    if Declaration <> nil then
    begin
      Exit(cTexts[TNestedRoutinesText.Overloaded].Text);
    end;
    Declaration := TypeBody[mIndex];
  end;
  Result := '';
  if Declaration = nil then
  begin
    Result := cTexts[TNestedRoutinesText.DeclarationMissing].Text;
  end;
end;

function TEmbedding.MethodDeclarationIssue: string;
begin
  TypeBody := TRoutineBody.TypeBody(Request.Tree.Root, QualifiedClass);
  if TypeBody = nil then
  begin
    Exit(cTexts[TNestedRoutinesText.ClassNotInTheFile].Fmt([QualifiedClass]));
  end;
  Result := FindDeclaration;
  if (Result = '') and not MatchText(TRoutineBody.VisibilityOf(TypeBody, Declaration),
    ['private', 'strict private']) then
  begin
    Result := cTexts[TNestedRoutinesText.NotPrivate].Text;
  end;
  if (Result = '') and TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract',
    'message', 'overload', 'reintroduce', 'final', 'static']) then
  begin
    Result := cTexts[TNestedRoutinesText.VirtualMessageOrOverloaded].Text;
  end;
end;

function TEmbedding.DeclaredIn(ASection: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    if (mChild <> Routine) and (mChild.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl]) and
      SameText(mChild.Name, Short) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TEmbedding.UnitDeclarationIssue: string;
var
  mSection: TSyntaxNode;
begin
  for mSection in TArray<TSyntaxNode>.Create(Request.Tree.Root.FindChild(TSyntaxKind.InterfaceSection),
    Routine.Parent) do
  begin
    if (mSection <> nil) and DeclaredIn(mSection) then
    begin
      Exit(cTexts[TNestedRoutinesText.AlsoDeclaredElsewhere].Text);
    end;
  end;
  Result := '';
end;

function TEmbedding.DeclarationIssue: string;
begin
  if IsMethod then
  begin
    Result := MethodDeclarationIssue;
  end
  else
  begin
    Result := UnitDeclarationIssue;
  end;
end;

function TEmbedding.IsSelfAccess(ANode: TSyntaxNode): Boolean;
begin
  Result := IsMethod and (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self');
end;

function TEmbedding.ReferenceIssue: string;
var
  mNode: TSyntaxNode;
  mReferences, mCandidates: TArray<TSyntaxNode>;
begin
  mReferences := nil;
  Recursive := False;
  mCandidates := Collected(Request.Tree.Root, TSyntaxKind.Identifier) +
    Collected(Request.Tree.Root, TSyntaxKind.MemberAccess);
  for mNode in mCandidates do
  begin
    if not SameText(mNode.Name, Short) then
    begin
      Continue;
    end;
    if (mNode.Kind = TSyntaxKind.MemberAccess) and not IsSelfAccess(mNode) then
    begin
      Exit(cTexts[TNestedRoutinesText.UsedViaAnotherObject].Text);
    end;
    if (mNode.Kind <> TSyntaxKind.MemberAccess) and TRoutineParts.Shadowed(Cache, mNode, nil, Short, False) then
    begin
      Continue;
    end;
    if TRoutineBody.Within(mNode, Routine) then
    begin
      Recursive := True;
      Continue;
    end;
    mReferences := mReferences + [mNode];
  end;
  if Length(mReferences) <> 1 then
  begin
    Exit(cTexts[TNestedRoutinesText.NotExactlyOneCall].Text);
  end;
  Reference := mReferences[0];
  Result := '';
end;

function TEmbedding.UsageIssue: string;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Call := nil;
  Arguments := nil;
  Result := '';
  mNode := Reference.Parent;
  if (mNode.Kind = TSyntaxKind.Call) and (mNode[0] = Reference) then
  begin
    Call := mNode;
    for mIndex := 1 to Call.ChildCount - 1 do
    begin
      Arguments := Arguments + [Call[mIndex]];
    end;
  end
  else if (mNode.Kind <> TSyntaxKind.CallStatement) and (not TRoutineParts.IsFunction(Routine) or
    (mNode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call, TSyntaxKind.AddressOf])) then
  begin
    Result := cTexts[TNestedRoutinesText.NotUsedAsACall].Text;
  end;
end;

function TEmbedding.CallerIssue: string;
begin
  Caller := Reference.Parent;
  while (Caller <> nil) and (Caller.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Caller := Caller.Parent;
  end;
  if (Caller = nil) or (Caller = Routine) or (Caller.Parent <> Routine.Parent) or
    not TRoutineBody.Within(Reference, TRoutineBody.BodyOf(Caller)) then
  begin
    Exit(cTexts[TNestedRoutinesText.CallerIsNotARoutine].Text);
  end;
  if IsMethod and (not SameText(TRoutineBody.QualifierOf(Caller.Name), QualifiedClass) or
    (TRoutineParts.IsClassHeader(Tokens, TRoutineParts.HeaderOf(Caller)) <> IsClass)) then
  begin
    Exit(cTexts[TNestedRoutinesText.CallerIsNotAMethod].Text);
  end;
  CallerBody := TRoutineBody.BodyOf(Caller);
  Result := UsageIssue;
end;

function TEmbedding.ParameterWritten(AIndex: Integer): Boolean;
begin
  Result := (Parameters[AIndex].Modifier = '') and WritesName(Cache, Identifiers, Routine, Parameters[AIndex].Name,
    Request.Lookup.Flow);
end;

function TEmbedding.TargetTaken(AIndex: Integer; const ATarget: string): Boolean;
begin
  Result := not SameText(ATarget, Parameters[AIndex].Name) and (Cache.Declares(Routine, ATarget, MaxInt) or
    UsesName(Identifiers, ATarget));
end;

function TEmbedding.IsPassThrough(AIndex: Integer; out ATarget: string): Boolean;
var
  mFound: Integer;
  mType: string;
begin
  ATarget := '';
  if Arguments[AIndex].Kind <> TSyntaxKind.Identifier then
  begin
    Exit(False);
  end;
  mFound := TRoutineLocals.IndexOf(CallerLocals, Arguments[AIndex].Name, Arguments[AIndex].StartOffset);
  if (mFound < 0) or not (CallerLocals[mFound].Kind in [TRoutineLocalKind.Parameter, TRoutineLocalKind.Variable]) then
  begin
    Exit(False);
  end;
  mType := Trim(Copy(Parameters[AIndex].Rest, 2, MaxInt));
  ATarget := CallerLocals[mFound].Name;
  Result := (mType <> '') and SameText(mType, CallerLocals[mFound].TypeText) and not TargetTaken(AIndex, ATarget) and
    not ParameterWritten(AIndex);
end;

function TEmbedding.PassThroughIssue: string;
var
  mIndex: Integer;
  mTarget: string;
  mAny: Boolean;
begin
  if Recursive then
  begin
    Exit(cTexts[TNestedRoutinesText.Recursive].Text);
  end;
  mAny := False;
  for mIndex := 0 to Min(High(Parameters), High(Arguments)) do
  begin
    if IsPassThrough(mIndex, mTarget) then
    begin
      Removed[mIndex] := True;
      Renamed.AddOrSetValue(LowerCase(Parameters[mIndex].Name), mTarget);
      mAny := True;
    end;
  end;
  Result := '';
  if not mAny then
  begin
    Result := cTexts[TNestedRoutinesText.NoParametersPassedThrough].Text;
  end;
end;

function TEmbedding.ParametersIssue: string;
var
  mIndex: Integer;
begin
  Parameters := TRoutineParts.ParameterTexts(Request.Text, Header);
  if UnreadableParameters(Header, Parameters) then
  begin
    Exit(cTexts[TNestedRoutinesText.UnsupportedParameters].Text);
  end;
  SetLength(Removed, Length(Parameters));
  for mIndex := 0 to High(Removed) do
  begin
    Removed[mIndex] := False;
  end;
  Identifiers := Collected(TRoutineBody.BodyOf(Routine), TSyntaxKind.Identifier);
  CallerLocals := Cache.Locals(Caller);
  Result := '';
  // Durchgereichte Parameter: Argument ist eine Variable oder ein Parameter des Aufrufers mit demselben Typ.
  if RemovePassThrough then
  begin
    Result := PassThroughIssue;
  end;
end;

function TEmbedding.CallerMembers: TArray<string>;
var
  mQualifier: string;
  mTypeBody: TSyntaxNode;
begin
  Result := nil;
  mQualifier := TRoutineBody.QualifierOf(Caller.Name);
  if IsMethod or (mQualifier = '') then
  begin
    Exit;
  end;
  mTypeBody := TRoutineBody.TypeBody(Request.Tree.Root, mQualifier);
  if mTypeBody <> nil then
  begin
    Result := TRoutineBody.MemberNames(mTypeBody);
  end;
end;

function TEmbedding.BodyNameIssue(ANode: TSyntaxNode; const AMembers: TArray<string>): string;
begin
  if TRoutineParts.Shadowed(Cache, ANode, Routine, ANode.Name, True) or Renamed.ContainsValue(ANode.Name) then
  begin
    Exit('');
  end;
  Result := '';
  if Cache.Declares(Caller, ANode.Name, CallerBody.StartOffset - 1) and not SameText(ANode.Name, 'Result') then
  begin
    Result := Caller.Name + cTexts[TNestedRoutinesText.Hides].Text + ANode.Name;
  end
  else if IndexText(ANode.Name, AMembers) >= 0 then
  begin
    Result := cTexts[TNestedRoutinesText.AMemberOfTheClass].Text + ANode.Name;
  end;
end;

function TEmbedding.TypeShadowIssue: string;
var
  mNode: TSyntaxNode;
begin
  for mNode in Collected(Routine, TSyntaxKind.TypeReference) do
  begin
    if not TRoutineParts.Shadowed(Cache, mNode, Routine, mNode.Name, True) and Cache.Declares(Caller, mNode.Name,
      CallerBody.StartOffset - 1) then
    begin
      Exit(Caller.Name + cTexts[TNestedRoutinesText.Hides].Text + mNode.Name);
    end;
  end;
  Result := '';
end;

function TEmbedding.ShadowIssue: string;
var
  mMembers: TArray<string>;
  mNode: TSyntaxNode;
begin
  if Cache.Declares(Caller, Short, CallerBody.StartOffset - 1) then
  begin
    Exit(Caller.Name + cTexts[TNestedRoutinesText.AlreadyKnows].Text + Short);
  end;
  mMembers := CallerMembers;
  for mNode in Identifiers do
  begin
    Result := BodyNameIssue(mNode, mMembers);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  Result := TypeShadowIssue;
  if (Result = '') and SameText(Short, 'Result') then
  begin
    Result := cTexts[TNestedRoutinesText.NameResult].Text;
  end;
end;

function TEmbedding.KeptParameters: TArray<TParameterText>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(Parameters) do
  begin
    if not Removed[mIndex] then
    begin
      Result := Result + [Parameters[mIndex]];
    end;
  end;
end;

function TEmbedding.BodyEdits(const AKept: TArray<TParameterText>): TArray<TOffsetEdit>;
var
  mNode: TSyntaxNode;
  mTarget: string;
begin
  Result := TArray<TOffsetEdit>.Create(TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
    TRoutineParts.HeadText(Request.Text, Header, Short, AKept, False)));
  for mNode in Identifiers do
  begin
    if Renamed.TryGetValue(LowerCase(mNode.Name), mTarget) and
      not TRoutineParts.Shadowed(Cache, mNode, Routine, mNode.Name, False) and not SameText(mNode.Name, mTarget) then
    begin
      Result := Result + [TOffsetEdit.Create(mNode.StartOffset, mNode.EndOffset, mTarget)];
    end;
  end;
end;

function TEmbedding.MovedText(const AKept: TArray<TParameterText>): string;
var
  mStart: Integer;
  mIndent: string;
begin
  mStart := Lines.OffsetAt(TTextPosition.Create(TRoutineBody.RoutineInsertLine(Request.Text, Routine), 0));
  Result := TRoutineParts.ApplyEdits(Copy(Request.Text, mStart + 1, Routine.EndOffset - mStart), mStart,
    BodyEdits(AKept));
  mIndent := TTextLines.IndentOf(Request.Text, Caller.StartPos.Line) + TRoutineBody.IndentUnit(Request.Style);
  Result := TRoutineBody.Reindent(TrimLeft(Result), TTextLines.IndentOf(Request.Text, Routine.StartPos.Line),
    mIndent, LineBreak);
end;

function TEmbedding.RemovalEdits: TArray<TTextEdit>;
var
  mTextLines: TArray<string>;
  mFirstLine, mEnd: Integer;
begin
  mTextLines := TTextLines.SplitLines(Request.Text);
  mFirstLine := TRoutineBody.RoutineInsertLine(Request.Text, Routine);
  mEnd := Routine.EndPos.Line + 1;
  if TRoutineParts.LineIsBlank(mTextLines, mFirstLine - 1) and TRoutineParts.LineIsBlank(mTextLines, mEnd) then
  begin
    Inc(mEnd);
  end;
  Result := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(mFirstLine, 0, mEnd, 0), ''));
  if Declaration <> nil then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(Declaration.StartPos.Line, 0,
      Declaration.EndPos.Line + 1, 0), '')];
  end;
end;

function TEmbedding.InsertEdit(const AMoved: string; ABeginLine: Integer): TTextEdit;
var
  mText: string;
begin
  if TRoutineParts.LineIsBlank(TTextLines.SplitLines(Request.Text), ABeginLine - 1) then
  begin
    mText := AMoved + LineBreak + LineBreak;
  end
  else
  begin
    mText := LineBreak + AMoved + LineBreak + LineBreak;
  end;
  Result := TTextEdit.Create(TTextRange.Create(ABeginLine, 0, ABeginLine, 0), mText);
end;

function TEmbedding.ArgumentText: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(Arguments) do
  begin
    if (mIndex <= High(Removed)) and Removed[mIndex] then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TRoutineBody.TextOf(Request.Text, Arguments[mIndex]);
  end;
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

function TEmbedding.CallEdits: TArray<TTextEdit>;
begin
  Result := nil;
  if Reference.Kind = TSyntaxKind.MemberAccess then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(Reference.StartPos, Reference.EndPos), Short)];
  end;
  if RemovePassThrough then
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(Call[0].EndPos, Call.EndPos), ArgumentText)];
  end;
end;

function TEmbedding.Title: string;
begin
  if IsMethod then
  begin
    Result := TNestedRoutines.EmbedMethodTitle;
  end
  else
  begin
    Result := TNestedRoutines.EmbedRoutineTitle;
  end;
  if RemovePassThrough then
  begin
    Result := Result + TNestedRoutines.PassThroughSuffix;
  end;
end;

function TEmbedding.BuildIssue(var AAction: TCodeAction): string;
var
  mKept: TArray<TParameterText>;
  mMoved: string;
  mBeginLine: Integer;
begin
  LineBreak := TTextLines.LineBreakOf(Request.Text);
  mKept := KeptParameters;
  mMoved := MovedText(mKept);
  mBeginLine := CallerBody.StartPos.Line;
  if CallerBody.StartPos.Character <> Length(TTextLines.IndentOf(Request.Text, mBeginLine)) then
  begin
    Exit(cTexts[TNestedRoutinesText.BeginOfTheCallerIs].Text);
  end;
  AAction.Title := Title;
  AAction.Kind := RewriteKind;
  AAction.Edits := RemovalEdits + [InsertEdit(mMoved, mBeginLine)] + CallEdits;
  AAction.Preview := cTexts[TNestedRoutinesText.NewLocalRoutineIn].Fmt([Caller.Name,
    TRoutineParts.HeadText(Request.Text, Header, Short, mKept, False)]) + LineBreak +
      cTexts[TNestedRoutinesText.ChangedCalls1].Text;
  Result := '';
end;

function TEmbedding.Run(var AAction: TCodeAction): string;
begin
  Result := ReferenceIssue;
  if Result = '' then
  begin
    Result := CallerIssue;
  end;
  if Result = '' then
  begin
    Result := ParametersIssue;
  end;
  if Result = '' then
  begin
    Result := ShadowIssue;
  end;
  if Result = '' then
  begin
    Result := BuildIssue(AAction);
  end;
end;

function EmbedCore(const ARequest: TNestedRoutineRequest; ARemovePassThrough: Boolean; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  mWork: TEmbedding;
begin
  AAction := Default(TCodeAction);
  mWork := Default(TEmbedding);
  mWork.Request := ARequest;
  mWork.RemovePassThrough := ARemovePassThrough;
  AReason := mWork.LocateIssue(ARequest.Position);
  if AReason = '' then
  begin
    AReason := mWork.DeclarationIssue;
  end;
  if AReason = '' then
  begin
    mWork.Cache := TLocalsCache.Create(ARequest.Text, ARequest.Tree);
    mWork.Renamed := TDictionary<string, string>.Create;
    try
      AReason := mWork.Run(AAction);
    finally
      mWork.Renamed.Free;
      mWork.Cache.Free;
    end;
  end;
  Result := AReason = '';
end;

{ TNestedRoutineRequest }

class function TNestedRoutineRequest.Create(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TNestedRoutineRequest;
begin
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Position := APosition;
  Result.Lookup := ALookup;
  Result.Style := AStyle;
end;

{ TNestedRoutines }

class function TNestedRoutines.Extract(const ARequest: TNestedRoutineRequest; out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := ExtractCore(ARequest, AAction, mReason);
end;

class function TNestedRoutines.Extract(const ARequest: TNestedRoutineRequest; out AAction: TCodeAction;
  out AReason: string): Boolean;
begin
  Result := ExtractCore(ARequest, AAction, AReason);
end;

class function TNestedRoutines.Embed(const ARequest: TNestedRoutineRequest; ARemovePassThrough: Boolean;
  out AAction: TCodeAction; out AReason: string): Boolean;
begin
  Result := EmbedCore(ARequest, ARemovePassThrough, AAction, AReason);
end;

class function TNestedRoutines.Embed(const ARequest: TNestedRoutineRequest; ARemovePassThrough: Boolean;
  out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := EmbedCore(ARequest, ARemovePassThrough, AAction, mReason);
end;

class function TNestedRoutines.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>;
var
  mRequest: TNestedRoutineRequest;
  mAction: TCodeAction;
begin
  Result := nil;
  mRequest := TNestedRoutineRequest.Create(AText, ATree, APosition, ALookup, AStyle);
  if Extract(mRequest, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if Embed(mRequest, False, mAction) then
  begin
    Result := Result + [mAction];
    if Embed(mRequest, True, mAction) then
    begin
      Result := Result + [mAction];
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.NestedRoutines', cTexts);

end.
