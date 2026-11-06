unit Atlas.Common.Rules.Builtin.Ownership;

// Regeln für Besitz von Objekten:
//   owned-item-freed  Element einer besitzenden Liste zusätzlich freigegeben (#947): Liste[I].Free,
//                     FreeAndNil(Liste[I]) oder Element.Free für ein Element aus Liste[I], Liste.First/Last bzw.
//                     "for Element in Liste do", während TObjectList/TObjectList<T> (OwnsObjects, Vorgabe True)
//                     bzw. TObjectDictionary mit doOwnsValues das Element selbst freigibt: bei Delete, Remove,
//                     Clear, einer Zuweisung an Liste[I] oder spätestens beim Freigeben der Liste. Besitzend ist
//                     eine Liste, wenn sie in der Unit so erzeugt wird (TObjectList ohne False, TObjectDictionary
//                     mit doOwnsValues) bzw. ohne Erzeugung als TObjectList deklariert ist, und kein
//                     "OwnsObjects := False" folgt. Extract in derselben Routine lässt die Regel schweigen.
//                     Korrekturen: Free entfernen, Delete bzw. Remove statt Free, Extract statt Remove.
//   create-without-assignment  "TStringList.Create;" als eigene Anweisung (#948): Das Objekt wird erzeugt, aber
//                     nirgends gespeichert und nie freigegeben. Still bleiben Komponenten mit Owner (erstes Argument
//                     Self, Owner, AOwner, Application bzw. ein Nachfahr von TComponent mit Argument ungleich nil),
//                     Threads (geben sich mit FreeOnTerminate selbst frei), unbekannte Klassen mit Argumenten und
//                     Klassen aus "selfRegistering". Korrektur: Zuweisung an eine neue lokale Variable, die
//                     folgenden Anweisungen des Blocks in try/finally mit Free.
//   self-as-interface-in-constructor  Self als Interface weitergegeben, während die Referenzzählung das Objekt
//                     freigeben kann (#950). Nur zwei echte Fehlerfälle: (1) Klassen mit eigener Referenzzählung
//                     (_Release in der Kette gibt das Objekt frei, kein NewInstance-Schutz, Kette bis TObject
//                     bekannt) im Konstruktor oder in AfterConstruction; (2) Nachfahren von TInterfacedObject in
//                     AfterConstruction nach inherited, das den Schutzzähler aus NewInstance schon abgebaut hat.
//                     Im Konstruktor von TInterfacedObject-Nachfahren ist Self geschützt und bleibt still. Als
//                     Weitergabe zählen Self as IX, IX(Self), ein Argument, dessen Parameter in allen bekannten
//                     Überladungen ein Interface ist, und die Zuweisung an eine Interface-Variable. Korrektur in
//                     Fall 2: die Anweisung vor inherited verschieben.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TOwnedItemFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Besitzt eine Liste, die mit ATypeName und den Argumenten AArguments von Create erzeugt wird,
    /// ihre Elemente? AIsDictionary meldet ein TObjectDictionary (besitzt nur mit doOwnsValues).</summary>
    class function CreatesOwning(const ATypeName, AArguments: string; out AIsDictionary: Boolean): Boolean; static;
  end;

  TCreateWithoutAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Folgt AName der Namensregel für Typen (TName, EName)?</summary>
    class function LooksLikeType(const AName: string): Boolean; static;
    /// <summary>Name der lokalen Variablen für die Korrektur: TImportProtokoll → ImportProtokoll.</summary>
    class function VariableName(const ATypeName: string): string; static;
  end;

  TSelfAsInterfaceInConstructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist ATypeName ein Interface nach der Namensregel (IName, auch Unit.IName, IList&lt;T&gt;)?</summary>
    class function IsInterfaceType(const AType: string): Boolean; static;
  end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Ownership.TryFinally,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TOwnershipText = (RemoveFree, InsteadOfFree, OwnsElements, OwnsValues, DoubleFree, DoubleFreeList, AssignAndFree,
    Lost, MoveBeforeInherited, InAfterConstruction, InConstructor, SelfInterface, SelfAfterConstruction,
    OwnedFreedTitle, LostTitle, SelfInterfaceTitle, InsteadOfRemove, AssignmentTo);

const
  cTexts: array[TOwnershipText] of TAtlasText = (
    (De: 'Free entfernen'; En: 'Remove Free'),
    (De: '%s statt Free'; En: '%s instead of Free'),
    (De: 'seine Elemente (OwnsObjects)'; En: 'its elements (OwnsObjects)'),
    (De: 'seine Werte (doOwnsValues)'; En: 'its values (doOwnsValues)'),
    (De: '%s besitzt %s; %s gibt das Element ein zweites Mal frei.';
     En: '%s owns %s; %s releases the element a second time.'),
    (De: '%s besitzt %s; die Liste gibt das Element beim Freigeben ein zweites Mal frei.';
     En: '%s owns %s; the list releases the element a second time when it is released.'),
    (De: 'An %s zuweisen und in try/finally freigeben'; En: 'Assign to %s and release in try/finally'),
    (De: 'Das erzeugte %s wird nirgends gespeichert und nie freigegeben (Speicherleck).';
     En: 'The created %s is stored nowhere and never released (memory leak).'),
    (De: 'Vor inherited verschieben'; En: 'Move before inherited'),
    (De: 'in AfterConstruction'; En: 'in AfterConstruction'),
    (De: 'im Konstruktor'; En: 'in the constructor'),
    (De: 'Self wird %s als Interface übergeben; die eigene Referenzzählung von %s gibt das Objekt frei, sobald der ' +
      'Zähler danach auf 0 fällt.';
     En: 'Self is passed as interface %s; the own reference counting of %s releases the object as soon as the ' +
      'counter then drops to 0.'),
    (De: 'Self wird nach inherited AfterConstruction als Interface übergeben; fällt der Zähler danach auf 0, ist das ' +
      'Objekt schon freigegeben.';
     En: 'Self is passed as interface after inherited AfterConstruction; if the counter then drops to 0, the object ' +
      'is already released.'),
    (De: 'Element einer besitzenden Liste zusätzlich freigegeben';
     En: 'Element of an owning list released additionally'),
    (De: 'Objekt erzeugt und sofort verloren'; En: 'Object created and lost immediately'),
    (De: 'Self als Interface im Konstruktor weitergegeben'; En: 'Self passed on as interface in the constructor'),
    (De: '%s statt Remove'; En: '%s instead of Remove'),
    (De: 'die Zuweisung an %s[…]'; En: 'the assignment to %s[…]'));

{$SCOPEDENUMS OFF}

const
  cOwnedItemFreedRuleId = 'owned-item-freed';
  cCreateWithoutAssignmentRuleId = 'create-without-assignment';
  cSelfAsInterfaceInConstructorRuleId = 'self-as-interface-in-constructor';
  cRemoveMethods: array[0..4] of string = ('Delete', 'Remove', 'RemoveItem', 'Clear', 'DeleteRange');
  cExtractMethods: array[0..3] of string = ('Extract', 'ExtractAt', 'ExtractItem', 'ExtractPair');

type
  /// <summary>Eine besitzende Liste der Unit.</summary>
  TOwningList = record
    Name: string;
    IsDictionary: Boolean;
  end;

  /// <summary>Art einer erzeugten Klasse für create-without-assignment.</summary>
{$SCOPEDENUMS ON}
  TCreatedKind = (Unknown, Plain, Component, Thread);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Freigabe eines Listenelements in einer Routine.</summary>
  TItemFree = record
    List: TOwningList;
    /// <summary>Code-Position des ersten und letzten Tokens des freigegebenen Ausdrucks.</summary>
    First, Last: Integer;
    /// <summary>Indexausdruck bei Liste[Index].Free, sonst leer.</summary>
    IndexText: string;
    /// <summary>Name der Elementvariablen bei Element.Free, sonst leer.</summary>
    Alias: string;
  end;

  /// <summary>Wie eine Liste in einer Routine ein Element entfernt.</summary>
  TItemRemoval = record
    /// <summary>Methode (Delete, Remove …) oder "die Zuweisung an …"; leer ohne.</summary>
    Text: string;
    /// <summary>Code-Position der Methode, -1 ohne.</summary>
    Position: Integer;
    /// <summary>Nimmt die Routine Elemente mit Extract heraus?</summary>
    Extracted: Boolean;
  end;

  /// <summary>Ein Aufruf T.Create(…) als eigene Anweisung.</summary>
  TCreateCall = record
    /// <summary>Code-Positionen: Beginn, Klassenname, Punkt vor Create, erstes Token nach dem Aufruf.</summary>
    Position, ClassPosition, After, Next: Integer;
    HasArguments: Boolean;
    /// <summary>Erstes Argument, wenn es ein Name oder nil ist; sonst leer.</summary>
    FirstArgument: string;
  end;

  /// <summary>Konstruktor oder AfterConstruction, in dem Self nicht als Interface weitergegeben werden darf.</summary>
  TConstruction = record
    TypeName: string;
    /// <summary>"im Konstruktor" bzw. "in AfterConstruction".</summary>
    Where: string;
    Block: TSyntaxNode;
    /// <summary>Hat die Klasse eine eigene Referenzzählung (Fall 1)?</summary>
    Counting: Boolean;
  end;

  /// <summary>Gemeinsame Grundlage der Regeln: Tokens ohne Kommentare und Direktiven, Zeilen der Datei.</summary>
  TOwnershipTokenScan = class
  protected
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    /// <summary>Indizes der Code-Tokens in FTokens, nach Offset sortiert.</summary>
    FCode: TArray<Integer>;
    FLines: TArray<string>;
    FLineBreak: string;
    function Token(APosition: Integer): TPascalToken;
    function IsWord(APosition: Integer): Boolean;
    function IsSym(APosition: Integer; const ASymbol: string): Boolean;
    function IsName(APosition: Integer; const AName: string): Boolean;
    function IsKey(APosition: Integer; const AKeyword: string): Boolean;
    function CodeAt(AOffset: Integer): Integer;
    function Closing(AOpen: Integer): Integer;
    function TextBetween(AFirst, ALast: Integer): string;
    function SkipGenericArgs(APosition: Integer): Integer;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Prüft eine Datei auf owned-item-freed.</summary>
  TOwnedItemFreedScan = class(TOwnershipTokenScan)
  private
    FLists: TArray<TOwningList>;
    FCreated: TArray<string>;
    FNotOwning: TArray<string>;
    FDeclared: TArray<string>;
    procedure AddList(const AName: string; AIsDictionary: Boolean);
    function SkipUnitPrefix(APosition: Integer): Integer;
    function CreateArguments(AOpen: Integer): string;
    procedure CollectCreation(APosition: Integer);
    function IsOwnsObjectsFalse(APosition: Integer): Boolean;
    procedure CollectDeclared(APosition: Integer);
    procedure CollectAt(APosition: Integer);
    procedure CollectLists;
    function ListAt(APosition: Integer; out AList: TOwningList): Boolean;
    function ElementAccess(APosition: Integer; out AAfter: Integer; out AIndex: string): Boolean;
    function FreeAfter(AExprLast: Integer): Boolean;
    function IsEndItem(APosition: Integer): Boolean;
    function IsElementRead(APosition: Integer): Boolean;
    function IsElementAssign(APosition: Integer; var AList: TOwningList): Boolean;
    function IsForInHead(APosition: Integer): Boolean;
    function IsLoopSource(APosition: Integer; const AList: TOwningList): Boolean;
    function FreeInLoop(APosition, AFreePosition: Integer): Boolean;
    function IsLoopAlias(APosition, AFreePosition: Integer; var AList: TOwningList): Boolean;
    function AliasList(ABlock: TSyntaxNode; AFreePosition: Integer; const AName: string;
      out AList: TOwningList): Boolean;
    function OwnStatement(APosition: Integer; out ANode: TSyntaxNode): Boolean;
    function RemoveFreeFix(APosition: Integer; out AFix: TRuleFix): Boolean;
    function DeleteFix(const AFree: TItemFree; out AFix: TRuleFix): Boolean;
    function FreeAndNilAt(ABlock: TSyntaxNode; APosition: Integer; var AItem: TItemFree): Boolean;
    function IndexedFreeAt(APosition: Integer; var AItem: TItemFree): Boolean;
    function AliasFreeAt(ABlock: TSyntaxNode; APosition: Integer; var AItem: TItemFree): Boolean;
    function FreeAt(ABlock: TSyntaxNode; APosition: Integer; out AItem: TItemFree): Boolean;
    function CollectFrees(ABlock: TSyntaxNode): TArray<TItemFree>;
    procedure NoteRemoval(APosition: Integer; var ARemoval: TItemRemoval);
    function RemovalOf(ABlock: TSyntaxNode; const AItem: TItemFree): TItemRemoval;
    function RemovalFixes(const AItem: TItemFree; const ARemoval: TItemRemoval): TArray<TRuleFix>;
    function ListFreeFixes(const AItem: TItemFree): TArray<TRuleFix>;
    procedure ReportFree(ABlock: TSyntaxNode; const AItem: TItemFree);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    procedure Run;
  end;

  /// <summary>Prüft eine Datei auf create-without-assignment.</summary>
  TCreateWithoutAssignmentScan = class(TOwnershipTokenScan)
  private
    FSelfRegistering: TArray<string>;
    FAncestry: TAncestry;
    function IsSelfRegistering(const AClassName: string): Boolean;
    function KindOf(const AClassName: string): TCreatedKind;
    function AssignFix(ARoutine, AStatement: TSyntaxNode; const ATypeText: string; out AFix: TRuleFix): Boolean;
    function FindCreate(var ACall: TCreateCall): Boolean;
    function ScanArguments(var ACall: TCreateCall): Boolean;
    function CreateCallAt(AStatement: TSyntaxNode; out ACall: TCreateCall): Boolean;
    function IsLost(const ACall: TCreateCall): Boolean;
    procedure ReportCreate(ARoutine, AStatement: TSyntaxNode; const ACall: TCreateCall);
    procedure CheckStatement(ARoutine, AStatement: TSyntaxNode);
    procedure VisitStatements(ARoutine, ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    procedure Run;
  end;

  /// <summary>Prüft eine Datei auf self-as-interface-in-constructor.</summary>
  TSelfAsInterfaceScan = class(TOwnershipTokenScan)
  private
    FAncestry: TAncestry;
    FTypes: TDeclaredTypes;
    function SymbolsNamed(const AName: string): TArray<TIndexSymbol>;
    function MethodBody(const AClassName, AMethod: string): TSyntaxNode;
    function Declares(const AClassName, AMethod: string): Boolean;
    function ReleaseFrees(const AClassName: string): Boolean;
    function OwnCounting(const AClassName: string): Boolean;
    function ExpectsInterface(const AName: string; AIndex: Integer): Boolean;
    function TargetIsInterface(APosition: Integer): Boolean;
    function IsAsInterface(APosition: Integer): Boolean;
    function IsInterfaceCast(APosition: Integer): Boolean;
    function IsStatementEnd(APosition: Integer): Boolean;
    function IsArgument(APosition: Integer): Boolean;
    function CallOpening(AStart: Integer; out AOpen, AArgument: Integer): Boolean;
    function ArgumentExpectsInterface(APosition: Integer): Boolean;
    function PassesAsInterface(APosition: Integer): Boolean;
    function OwnLines(AStatement: TSyntaxNode): Boolean;
    function MoveFix(ABlock: TSyntaxNode; AInherited, AOffset: Integer): TArray<TRuleFix>;
    function ConstructionRoutine(ARoutine: TSyntaxNode; out AInfo: TConstruction): Boolean;
    procedure ReportSelf(const AInfo: TConstruction; APosition, AInheritedAt: Integer);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    procedure Run;
  end;

/// <summary>Liegt die Stelle AOffset im Block ABlock?</summary>
function InBlock(ABlock: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (AOffset >= ABlock.StartOffset) and (AOffset < ABlock.EndOffset);
end;

function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mNext: TSyntaxNode;
begin
  // Iterativ (Bericht M1): je Ebene in das erste Kind, das AOffset enthält.
  Result := ANode;
  repeat
    mNext := nil;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if InBlock(Result[mIndex], AOffset) then
      begin
        mNext := Result[mIndex];
        Break;
      end;
    end;
    if mNext <> nil then
    begin
      Result := mNext;
    end;
  until mNext = nil;
end;

/// <summary>Korrektur Extract bzw. ExtractPair statt Remove am Token AToken.</summary>
function ExtractFix(const AToken: TPascalToken; AIsDictionary: Boolean): TRuleFix;
var
  mMethod: string;
begin
  mMethod := 'Extract';
  if AIsDictionary then
  begin
    mMethod := 'ExtractPair';
  end;
  Result := TRuleFix.Create(cTexts[TOwnershipText.InsteadOfRemove].Fmt([mMethod]),
    [TTextEdit.Create(TTextRange.Create(AToken.StartPos,
    AToken.EndPos), mMethod)]);
end;

/// <summary>Anweisung direkt im Rumpf ABlock, die AOffset enthält; nil sonst.</summary>
function TopStatement(ABlock: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if InBlock(ABlock[mIndex], AOffset) then
    begin
      Exit(ABlock[mIndex]);
    end;
  end;
  Result := nil;
end;

{ TOwnershipTokenScan }

constructor TOwnershipTokenScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mIndex: Integer;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FCode := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if not (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      FCode := FCode + [mIndex];
    end;
  end;
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
end;

function TOwnershipTokenScan.Token(APosition: Integer): TPascalToken;
begin
  Result := FTokens[FCode[APosition]];
end;

function TOwnershipTokenScan.IsWord(APosition: Integer): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and
    (Token(APosition).Kind = TPascalTokenKind.Identifier);
end;

function TOwnershipTokenScan.IsSym(APosition: Integer; const ASymbol: string): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and Token(APosition).IsSymbol(ASymbol);
end;

function TOwnershipTokenScan.IsName(APosition: Integer; const AName: string): Boolean;
begin
  Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
end;

function TOwnershipTokenScan.IsKey(APosition: Integer; const AKeyword: string): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and Token(APosition).IsKeyword(AKeyword);
end;

function TOwnershipTokenScan.CodeAt(AOffset: Integer): Integer;
var
  mHigh, mMiddle: Integer;
begin
  // Binär statt ab Dateianfang mit einer Kopie je Token: FCode steht nach Offset sortiert (#1342).
  Result := 0;
  mHigh := Length(FCode);
  while Result < mHigh do
  begin
    mMiddle := (Result + mHigh) div 2;
    if FTokens[FCode[mMiddle]].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
end;

/// <summary>Passende schließende Klammer zu AOpen ("(" oder "["), sonst -1.</summary>
function TOwnershipTokenScan.Closing(AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AOpen to High(FCode) do
  begin
    if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

function TOwnershipTokenScan.TextBetween(AFirst, ALast: Integer): string;
begin
  Result := Copy(FContext.Text, Token(AFirst).Offset + 1,
    Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
end;

/// <summary>Position nach den generischen Argumenten "&lt;…&gt;" ab APosition.</summary>
function TOwnershipTokenScan.SkipGenericArgs(APosition: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := APosition;
  if not IsSym(Result, '<') then
  begin
    Exit;
  end;
  mDepth := 0;
  while Result <= High(FCode) do
  begin
    if Token(Result).IsSymbol('<') then
    begin
      Inc(mDepth);
    end
    else if Token(Result).IsSymbol('>') then
    begin
      Dec(mDepth);
    end
    else if Token(Result).IsSymbol('>>') then
    begin
      Dec(mDepth, 2);
    end
    else if Token(Result).IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
    if mDepth <= 0 then
    begin
      Exit;
    end;
  end;
end;

{ TOwnedItemFreedScan }

procedure TOwnedItemFreedScan.AddList(const AName: string; AIsDictionary: Boolean);
var
  mItem: TOwningList;
begin
  for mItem in FLists do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit;
    end;
  end;
  mItem.Name := AName;
  mItem.IsDictionary := AIsDictionary;
  FLists := FLists + [mItem];
end;

/// <summary>Position des Typnamens nach "Unit.Unit." ab APosition.</summary>
function TOwnedItemFreedScan.SkipUnitPrefix(APosition: Integer): Integer;
begin
  Result := APosition;
  while IsWord(Result) and IsSym(Result + 1, '.') and IsWord(Result + 2) and
    not SameText(Token(Result).Text, 'TObjectList') and not SameText(Token(Result).Text, 'TObjectDictionary') do
  begin
    Inc(Result, 2);
  end;
end;

/// <summary>Text der Argumente von Create, wenn bei AOpen "(" steht; sonst leer.</summary>
function TOwnedItemFreedScan.CreateArguments(AOpen: Integer): string;
var
  mClose: Integer;
begin
  Result := '';
  if IsSym(AOpen, '(') then
  begin
    mClose := Closing(AOpen);
    if mClose > AOpen + 1 then
    begin
      Result := TextBetween(AOpen + 1, mClose - 1);
    end;
  end;
end;

/// <summary>Name := TObjectList&lt;T&gt;.Create(…);</summary>
procedure TOwnedItemFreedScan.CollectCreation(APosition: Integer);
var
  mTypePosition, mAfter: Integer;
  mIsDictionary: Boolean;
  mArguments: string;
begin
  mTypePosition := SkipUnitPrefix(APosition + 2);
  if not IsName(mTypePosition, 'TObjectList') and not IsName(mTypePosition, 'TObjectDictionary') then
  begin
    Exit;
  end;
  mAfter := SkipGenericArgs(mTypePosition + 1);
  if not IsSym(mAfter, '.') or not IsName(mAfter + 1, 'Create') then
  begin
    Exit;
  end;
  mArguments := CreateArguments(mAfter + 2);
  FCreated := FCreated + [Token(APosition).Text];
  if TOwnedItemFreedRule.CreatesOwning(Token(mTypePosition).Text, mArguments, mIsDictionary) then
  begin
    AddList(Token(APosition).Text, mIsDictionary);
  end
  else
  begin
    FNotOwning := FNotOwning + [Token(APosition).Text];
  end;
end;

/// <summary>Name.OwnsObjects := False;</summary>
function TOwnedItemFreedScan.IsOwnsObjectsFalse(APosition: Integer): Boolean;
begin
  Result := IsSym(APosition + 1, '.') and IsName(APosition + 2, 'OwnsObjects') and IsSym(APosition + 3, ':=') and
    IsName(APosition + 4, 'False');
end;

/// <summary>A, B: TObjectList; – die Namen stehen vor APosition durch Kommas getrennt.</summary>
procedure TOwnedItemFreedScan.CollectDeclared(APosition: Integer);
var
  mNames: Integer;
begin
  mNames := APosition;
  while IsWord(mNames) do
  begin
    FDeclared := FDeclared + [Token(mNames).Text];
    if not IsSym(mNames - 1, ',') then
    begin
      Break;
    end;
    Dec(mNames, 2);
  end;
end;

procedure TOwnedItemFreedScan.CollectAt(APosition: Integer);
begin
  if IsSym(APosition + 1, ':=') then
  begin
    CollectCreation(APosition);
  end
  else if IsOwnsObjectsFalse(APosition) then
  begin
    FNotOwning := FNotOwning + [Token(APosition).Text];
  end
  else if IsSym(APosition + 1, ':') and IsName(SkipUnitPrefix(APosition + 2), 'TObjectList') then
  begin
    CollectDeclared(APosition);
  end;
end;

/// <summary>Besitzende Listen der Unit: Erzeugungen, sonst Deklarationen als TObjectList; ohne
/// OwnsObjects := False.</summary>
procedure TOwnedItemFreedScan.CollectLists;
var
  mPosition, mIndex: Integer;
  mName: string;
begin
  FLists := nil;
  FCreated := nil;
  FNotOwning := nil;
  FDeclared := nil;
  for mPosition := 0 to High(FCode) - 2 do
  begin
    if IsWord(mPosition) then
    begin
      CollectAt(mPosition);
    end;
  end;
  for mName in FDeclared do
  begin
    if IndexText(mName, FCreated) < 0 then
    begin
      AddList(mName, False);
    end;
  end;
  for mIndex := High(FLists) downto 0 do
  begin
    if IndexText(FLists[mIndex].Name, FNotOwning) >= 0 then
    begin
      Delete(FLists, mIndex, 1);
    end;
  end;
end;

function TOwnedItemFreedScan.ListAt(APosition: Integer; out AList: TOwningList): Boolean;
var
  mItem: TOwningList;
begin
  Result := False;
  // Nur der Name selbst oder Self.Name, keine fremden Objekte.
  if not IsWord(APosition) or (IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'Self')) then
  begin
    Exit;
  end;
  for mItem in FLists do
  begin
    if SameText(mItem.Name, Token(APosition).Text) then
    begin
      AList := mItem;
      Exit(True);
    end;
  end;
end;

/// <summary>Liste[Index] bzw. Liste.Items[Index] ab APosition; liefert die Position nach "]" und den
/// Indextext.</summary>
function TOwnedItemFreedScan.ElementAccess(APosition: Integer; out AAfter: Integer; out AIndex: string): Boolean;
var
  mOpen, mClose: Integer;
begin
  Result := False;
  mOpen := APosition + 1;
  if IsSym(mOpen, '.') and IsName(mOpen + 1, 'Items') then
  begin
    Inc(mOpen, 2);
  end;
  if not IsSym(mOpen, '[') then
  begin
    Exit;
  end;
  mClose := Closing(mOpen);
  if mClose < 0 then
  begin
    Exit;
  end;
  AIndex := Trim(TextBetween(mOpen + 1, mClose - 1));
  AAfter := mClose + 1;
  Result := True;
end;

/// <summary>Steht nach AExprLast (letztes Token von X) eine Freigabe ".Free", ".Destroy", ".DisposeOf"?</summary>
function TOwnedItemFreedScan.FreeAfter(AExprLast: Integer): Boolean;
begin
  Result := IsSym(AExprLast + 1, '.') and (IsName(AExprLast + 2, 'Free') or IsName(AExprLast + 2, 'Destroy') or
    IsName(AExprLast + 2, 'DisposeOf'));
end;

/// <summary>Liste.First; bzw. Liste.Last; ab der Liste bei APosition.</summary>
function TOwnedItemFreedScan.IsEndItem(APosition: Integer): Boolean;
begin
  Result := IsSym(APosition + 1, '.') and (IsName(APosition + 2, 'First') or IsName(APosition + 2, 'Last')) and
    IsSym(APosition + 3, ';');
end;

/// <summary>Liste[I]; Liste.Items[I]; Liste.First; Liste.Last; ab der Liste bei APosition.</summary>
function TOwnedItemFreedScan.IsElementRead(APosition: Integer): Boolean;
var
  mAfter: Integer;
  mIndex: string;
begin
  Result := (ElementAccess(APosition, mAfter, mIndex) and IsSym(mAfter, ';')) or IsEndItem(APosition);
end;

/// <summary>V := Liste[I]; V := Liste.Items[I]; V := Liste.First mit V bei APosition.</summary>
function TOwnedItemFreedScan.IsElementAssign(APosition: Integer; var AList: TOwningList): Boolean;
begin
  Result := IsSym(APosition + 1, ':=') and ListAt(APosition + 2, AList) and IsElementRead(APosition + 2);
end;

/// <summary>for V in bzw. for var V in mit V bei APosition.</summary>
function TOwnedItemFreedScan.IsForInHead(APosition: Integer): Boolean;
begin
  Result := (APosition > 1) and (Token(APosition - 1).IsKeyword('for') or (Token(APosition - 1).IsKeyword('var') and
    Token(APosition - 2).IsKeyword('for'))) and Token(APosition + 1).IsKeyword('in');
end;

/// <summary>"do" nach einer Liste bzw. ".Values" nach einem Dictionary bei APosition.</summary>
function TOwnedItemFreedScan.IsLoopSource(APosition: Integer; const AList: TOwningList): Boolean;
begin
  if AList.IsDictionary then
  begin
    Result := IsSym(APosition, '.') and IsName(APosition + 1, 'Values');
  end
  else
  begin
    Result := Token(APosition).IsKeyword('do');
  end;
end;

/// <summary>Steht die Freigabe bei AFreePosition in der for-in-Schleife, deren Variable bei APosition steht?</summary>
function TOwnedItemFreedScan.FreeInLoop(APosition, AFreePosition: Integer): Boolean;
var
  mNode: TSyntaxNode;
begin
  mNode := NodeAt(FContext.Tree.Root, Token(APosition).Offset);
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.ForInStatement) do
  begin
    mNode := mNode.Parent;
  end;
  Result := (mNode <> nil) and (Token(AFreePosition).Offset < mNode.EndOffset);
end;

/// <summary>for V in Liste do / for V in Dictionary.Values do: nur, wenn die Freigabe in der Schleife steht.</summary>
function TOwnedItemFreedScan.IsLoopAlias(APosition, AFreePosition: Integer; var AList: TOwningList): Boolean;
begin
  Result := IsForInHead(APosition) and ListAt(APosition + 2, AList) and IsLoopSource(APosition + 3, AList) and
    FreeInLoop(APosition, AFreePosition);
end;

/// <summary>Elementvariablen der Routine: V := L[I], V := L.Items[I], L.First/Last, for V in L / L.Values.</summary>
function TOwnedItemFreedScan.AliasList(ABlock: TSyntaxNode; AFreePosition: Integer; const AName: string;
  out AList: TOwningList): Boolean;
var
  mPosition: Integer;
begin
  Result := False;
  for mPosition := 0 to AFreePosition - 1 do
  begin
    if (Token(mPosition).Offset >= ABlock.StartOffset) and IsName(mPosition, AName) and
      (IsElementAssign(mPosition, AList) or IsLoopAlias(mPosition, AFreePosition, AList)) then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Anweisung (CallStatement) um APosition, wenn sie allein in ihren Zeilen in einem Block steht. Ist sie
/// der einzige Rumpf einer for-in-Schleife, die ganze Schleife.</summary>
function TOwnedItemFreedScan.OwnStatement(APosition: Integer; out ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mRest: string;
begin
  Result := False;
  mNode := NodeAt(FContext.Tree.Root, Token(APosition).Offset);
  while (mNode <> nil) and (mNode.Kind <> TSyntaxKind.CallStatement) do
  begin
    mNode := mNode.Parent;
  end;
  if (mNode = nil) or (mNode.Parent = nil) then
  begin
    Exit;
  end;
  if (mNode.Parent.Kind = TSyntaxKind.ForInStatement) and (mNode.Parent[mNode.Parent.ChildCount - 1] = mNode) then
  begin
    mNode := mNode.Parent;
  end;
  if (mNode.Parent = nil) or not (mNode.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement]) or
    (mNode.StartPos.Line > High(FLines)) or (mNode.EndPos.Line > High(FLines)) then
  begin
    Exit;
  end;
  mRest := Trim(Copy(FLines[mNode.EndPos.Line], mNode.EndPos.Character + 1, MaxInt));
  if (Trim(Copy(FLines[mNode.StartPos.Line], 1, mNode.StartPos.Character)) <> '') or
    ((mRest <> '') and (mRest <> ';')) then
  begin
    Exit;
  end;
  ANode := mNode;
  Result := True;
end;

function TOwnedItemFreedScan.RemoveFreeFix(APosition: Integer; out AFix: TRuleFix): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := OwnStatement(APosition, mNode);
  if Result then
  begin
    AFix := TRuleFix.Create(cTexts[TOwnershipText.RemoveFree].Text,
      [TTextEdit.Create(TTextRange.Create(mNode.StartPos.Line, 0, mNode.EndPos.Line + 1, 0), '')]);
  end;
end;

/// <summary>Liste[I].Free → Liste.Delete(I) bzw. Dictionary.Remove(Key).</summary>
function TOwnedItemFreedScan.DeleteFix(const AFree: TItemFree; out AFix: TRuleFix): Boolean;
var
  mNode: TSyntaxNode;
  mMethod, mPrefix: string;
begin
  Result := (AFree.IndexText <> '') and OwnStatement(AFree.First, mNode) and
    (mNode.Kind = TSyntaxKind.CallStatement);
  if not Result then
  begin
    Exit;
  end;
  mMethod := 'Delete';
  if AFree.List.IsDictionary then
  begin
    mMethod := 'Remove';
  end;
  // "Self.Liste[I].Free": Self. bleibt stehen.
  mPrefix := '';
  if IsSym(AFree.First - 1, '.') then
  begin
    mPrefix := 'Self.';
  end;
  AFix := TRuleFix.Create(cTexts[TOwnershipText.InsteadOfFree].Fmt([mMethod]),
    [TTextEdit.Create(TTextRange.Create(mNode.StartPos, mNode.EndPos),
    Format('%s%s.%s(%s)', [mPrefix, Token(AFree.First).Text, mMethod, AFree.IndexText]))]);
end;

/// <summary>FreeAndNil(Liste[I]) bzw. FreeAndNil(V) mit FreeAndNil bei APosition.</summary>
function TOwnedItemFreedScan.FreeAndNilAt(ABlock: TSyntaxNode; APosition: Integer; var AItem: TItemFree): Boolean;
var
  mStart, mAfter: Integer;
  mList: TOwningList;
  mIndex: string;
begin
  mStart := APosition + 2;
  if IsName(mStart, 'Self') and IsSym(mStart + 1, '.') then
  begin
    Inc(mStart, 2);
  end;
  Result := True;
  if ListAt(mStart, mList) and ElementAccess(mStart, mAfter, mIndex) and IsSym(mAfter, ')') then
  begin
    AItem.List := mList;
    AItem.First := mStart;
    AItem.Last := mAfter;
    AItem.IndexText := mIndex;
  end
  else if IsWord(mStart) and IsSym(mStart + 1, ')') and AliasList(ABlock, APosition, Token(mStart).Text, mList) then
  begin
    AItem.List := mList;
    AItem.First := APosition;
    AItem.Last := mStart + 1;
    AItem.Alias := Token(mStart).Text;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Liste[I].Free mit der Liste bei APosition.</summary>
function TOwnedItemFreedScan.IndexedFreeAt(APosition: Integer; var AItem: TItemFree): Boolean;
var
  mAfter: Integer;
  mList: TOwningList;
  mIndex: string;
begin
  Result := ListAt(APosition, mList) and ElementAccess(APosition, mAfter, mIndex) and FreeAfter(mAfter - 1);
  if Result then
  begin
    AItem.List := mList;
    AItem.First := APosition;
    AItem.Last := mAfter + 1;
    AItem.IndexText := mIndex;
  end;
end;

/// <summary>V.Free für eine Elementvariable V bei APosition.</summary>
function TOwnedItemFreedScan.AliasFreeAt(ABlock: TSyntaxNode; APosition: Integer; var AItem: TItemFree): Boolean;
var
  mList: TOwningList;
begin
  Result := IsWord(APosition) and not IsSym(APosition - 1, '.') and FreeAfter(APosition) and
    AliasList(ABlock, APosition, Token(APosition).Text, mList);
  if Result then
  begin
    AItem.List := mList;
    AItem.First := APosition;
    AItem.Last := APosition + 2;
    AItem.Alias := Token(APosition).Text;
  end;
end;

/// <summary>Freigabe eines Listenelements bei APosition?</summary>
function TOwnedItemFreedScan.FreeAt(ABlock: TSyntaxNode; APosition: Integer; out AItem: TItemFree): Boolean;
begin
  AItem := Default(TItemFree);
  if IsName(APosition, 'FreeAndNil') and IsSym(APosition + 1, '(') then
  begin
    Result := FreeAndNilAt(ABlock, APosition, AItem);
  end
  else
  begin
    Result := IndexedFreeAt(APosition, AItem) or AliasFreeAt(ABlock, APosition, AItem);
  end;
end;

/// <summary>Freigaben von Listenelementen im Block ABlock.</summary>
function TOwnedItemFreedScan.CollectFrees(ABlock: TSyntaxNode): TArray<TItemFree>;
var
  mPosition: Integer;
  mItem: TItemFree;
begin
  Result := nil;
  for mPosition := 0 to High(FCode) do
  begin
    if InBlock(ABlock, Token(mPosition).Offset) and FreeAt(ABlock, mPosition, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Extract, Entfernen (Delete, Remove …) oder Zuweisung an Liste[…] an der Liste bei APosition; das erste
/// Entfernen zählt.</summary>
procedure TOwnedItemFreedScan.NoteRemoval(APosition: Integer; var ARemoval: TItemRemoval);
var
  mAfter: Integer;
  mIndex: string;
begin
  if IsSym(APosition + 1, '.') and (IndexText(Token(APosition + 2).Text, cExtractMethods) >= 0) then
  begin
    ARemoval.Extracted := True;
  end
  else if ARemoval.Text <> '' then
  begin
    // Das erste Entfernen ist schon gemerkt.
  end
  else if IsSym(APosition + 1, '.') and (IndexText(Token(APosition + 2).Text, cRemoveMethods) >= 0) then
  begin
    ARemoval.Text := Token(APosition + 2).Text;
    ARemoval.Position := APosition + 2;
  end
  else if ElementAccess(APosition, mAfter, mIndex) and IsSym(mAfter, ':=') then
  begin
    ARemoval.Text := cTexts[TOwnershipText.AssignmentTo].Fmt([Token(APosition).Text]);
  end;
end;

/// <summary>Entfernen bzw. Extract derselben Liste im Block ABlock.</summary>
function TOwnedItemFreedScan.RemovalOf(ABlock: TSyntaxNode; const AItem: TItemFree): TItemRemoval;
var
  mPosition: Integer;
  mList: TOwningList;
begin
  Result := Default(TItemRemoval);
  Result.Position := -1;
  for mPosition := 0 to High(FCode) - 2 do
  begin
    if InBlock(ABlock, Token(mPosition).Offset) and ListAt(mPosition, mList) and
      SameText(mList.Name, AItem.List.Name) then
    begin
      NoteRemoval(mPosition, Result);
    end;
  end;
end;

/// <summary>Korrekturen bei Entfernen vor der Freigabe: Free entfernen, Extract statt Remove.</summary>
function TOwnedItemFreedScan.RemovalFixes(const AItem: TItemFree; const ARemoval: TItemRemoval): TArray<TRuleFix>;
var
  mFix: TRuleFix;
begin
  Result := nil;
  if RemoveFreeFix(AItem.First, mFix) then
  begin
    Result := Result + [mFix];
  end;
  // Remove(V) vor V.Free: Extract nimmt das Element heraus, ohne es freizugeben.
  if (ARemoval.Position >= 0) and SameText(Token(ARemoval.Position).Text, 'Remove') and (AItem.Alias <> '') then
  begin
    mFix := ExtractFix(Token(ARemoval.Position), AItem.List.IsDictionary);
    mFix.Alternative := Result <> nil;
    Result := Result + [mFix];
  end;
end;

/// <summary>Korrekturen, wenn erst die Liste das Element freigibt: Delete bzw. Remove statt Free, Free
/// entfernen.</summary>
function TOwnedItemFreedScan.ListFreeFixes(const AItem: TItemFree): TArray<TRuleFix>;
var
  mFix: TRuleFix;
begin
  Result := nil;
  if DeleteFix(AItem, mFix) then
  begin
    Result := Result + [mFix];
  end
  else if (AItem.Alias <> '') and RemoveFreeFix(AItem.First, mFix) then
  begin
    Result := Result + [mFix];
  end;
end;

procedure TOwnedItemFreedScan.ReportFree(ABlock: TSyntaxNode; const AItem: TItemFree);
var
  mRemoval: TItemRemoval;
  mMessage, mOwns: string;
  mFixes: TArray<TRuleFix>;
begin
  mRemoval := RemovalOf(ABlock, AItem);
  if mRemoval.Extracted then
  begin
    Exit;
  end;
  mOwns := cTexts[TOwnershipText.OwnsElements].Text;
  if AItem.List.IsDictionary then
  begin
    mOwns := cTexts[TOwnershipText.OwnsValues].Text;
  end;
  if mRemoval.Text <> '' then
  begin
    mMessage := cTexts[TOwnershipText.DoubleFree].Fmt([AItem.List.Name, mOwns,
      mRemoval.Text]);
    mFixes := RemovalFixes(AItem, mRemoval);
  end
  else
  begin
    mMessage := cTexts[TOwnershipText.DoubleFreeList].Fmt([AItem.List.Name, mOwns]);
    mFixes := ListFreeFixes(AItem);
  end;
  FReport.Add(TTextRange.Create(Token(AItem.First).StartPos, Token(AItem.Last).EndPos), mMessage, mFixes);
end;

procedure TOwnedItemFreedScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mBlock: TSyntaxNode;
  mItem: TItemFree;
begin
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  if mBlock <> nil then
  begin
    for mItem in CollectFrees(mBlock) do
    begin
      ReportFree(mBlock, mItem);
    end;
  end;
end;

procedure TOwnedItemFreedScan.Visit(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        CheckRoutine(mNode);
        Continue;
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

procedure TOwnedItemFreedScan.Run;
begin
  CollectLists;
  if FLists <> nil then
  begin
    Visit(FContext.Tree.Root);
  end;
end;

{ TCreateWithoutAssignmentScan }

function TCreateWithoutAssignmentScan.IsSelfRegistering(const AClassName: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in FSelfRegistering do
  begin
    if MatchesGlob(mPattern, AClassName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Art der Klasse über die Vorfahren in Datei und Index; Unknown, wenn die Kette vor TObject
/// abbricht.</summary>
function TCreateWithoutAssignmentScan.KindOf(const AClassName: string): TCreatedKind;
var
  mName: string;
  mDepth: Integer;
  mBody: TSyntaxNode;
begin
  Result := TCreatedKind.Unknown;
  // Records (TPoint.Create(1, 2)) belegen keinen Heap.
  mBody := TRoutineBody.TypeBody(FContext.Tree.Root, AClassName);
  if (mBody <> nil) and (mBody.Kind = TSyntaxKind.RecordType) then
  begin
    Exit;
  end;
  mName := AClassName;
  mDepth := 0;
  while (mName <> '') and (mDepth < 64) do
  begin
    if SameText(mName, 'TComponent') then
    begin
      Exit(TCreatedKind.Component);
    end;
    if SameText(mName, 'TThread') then
    begin
      Exit(TCreatedKind.Thread);
    end;
    if SameText(mName, 'TObject') then
    begin
      Exit(TCreatedKind.Plain);
    end;
    mName := FAncestry.ParentOf(mName);
    Inc(mDepth);
  end;
end;

/// <summary>"Name := T.Create(…);" mit try/finally um die folgenden Anweisungen des Blocks.</summary>
function TCreateWithoutAssignmentScan.AssignFix(ARoutine, AStatement: TSyntaxNode; const ATypeText: string;
  out AFix: TRuleFix): Boolean;
var
  mName: string;
  mEdit: TTextEdit;
begin
  mName := TRoutineBody.UniqueName(FTokens,
    FContext.NewNames.Local(TCreateWithoutAssignmentRule.VariableName(ATypeText)));
  Result := TTryFinallyWrap.Create(FLines, FLineBreak, FContext.Formatting).Wrap(AStatement, mName + ' := ',
    mName + '.Free;', mEdit);
  if Result then
  begin
    AFix := TRuleFix.Create(cTexts[TOwnershipText.AssignAndFree].Fmt([mName]),
      [TRoutineBody.AddVariable(FContext.Text, ARoutine, mName, ATypeText, FContext.Formatting), mEdit]);
  end;
end;

/// <summary>Unit.TKlasse&lt;T&gt;.Create ab ACall.Position: Klassenname und Punkt vor Create.</summary>
function TCreateWithoutAssignmentScan.FindCreate(var ACall: TCreateCall): Boolean;
begin
  ACall.ClassPosition := ACall.Position;
  ACall.After := SkipGenericArgs(ACall.Position + 1);
  while IsSym(ACall.After, '.') and IsWord(ACall.After + 1) and not SameText(Token(ACall.After + 1).Text, 'Create') do
  begin
    ACall.ClassPosition := ACall.After + 1;
    ACall.After := SkipGenericArgs(ACall.After + 2);
  end;
  Result := IsSym(ACall.After, '.') and IsWord(ACall.After + 1) and SameText(Token(ACall.After + 1).Text, 'Create');
  ACall.Next := ACall.After + 2;
end;

/// <summary>Argumentliste nach Create: erstes Argument merken, ACall.Next dahinter; False bei offener
/// Klammer.</summary>
function TCreateWithoutAssignmentScan.ScanArguments(var ACall: TCreateCall): Boolean;
var
  mOpen, mClose: Integer;
begin
  Result := True;
  mOpen := ACall.Next;
  if not IsSym(mOpen, '(') then
  begin
    Exit;
  end;
  mClose := Closing(mOpen);
  if mClose < 0 then
  begin
    Exit(False);
  end;
  ACall.HasArguments := mClose > mOpen + 1;
  if ACall.HasArguments and (IsWord(mOpen + 1) or Token(mOpen + 1).IsKeyword('nil')) and
    (IsSym(mOpen + 2, ',') or IsSym(mOpen + 2, ')')) then
  begin
    ACall.FirstArgument := Token(mOpen + 1).Text;
  end;
  ACall.Next := mClose + 1;
end;

/// <summary>Ist AStatement ein Aufruf T.Create(…), der mit dem Aufruf endet?</summary>
function TCreateWithoutAssignmentScan.CreateCallAt(AStatement: TSyntaxNode; out ACall: TCreateCall): Boolean;
begin
  ACall := Default(TCreateCall);
  ACall.Position := CodeAt(AStatement.StartOffset);
  Result := IsWord(ACall.Position) and FindCreate(ACall) and ScanArguments(ACall);
  // Die Anweisung endet mit Create(…): nichts wird weitergegeben oder gespeichert.
  Result := Result and ((ACall.Next > High(FCode)) or (Token(ACall.Next).Offset >= AStatement.EndOffset));
end;

/// <summary>Bleibt das erzeugte Objekt ohne Besitzer? Komponenten mit Owner gibt der Owner frei; unbekannte
/// Klassen mit Argumenten tragen sich oft selbst ein. Mit Argumenten zählen nur bekannte Klassen ohne TComponent
/// und Aufrufe mit nil als Owner.</summary>
function TCreateWithoutAssignmentScan.IsLost(const ACall: TCreateCall): Boolean;
var
  mClassName: string;
  mKind: TCreatedKind;
begin
  mClassName := Token(ACall.ClassPosition).Text;
  mKind := KindOf(mClassName);
  if (not TCreateWithoutAssignmentRule.LooksLikeType(mClassName) and (mKind = TCreatedKind.Unknown)) or
    IsSelfRegistering(mClassName) or (mKind = TCreatedKind.Thread) then
  begin
    Exit(False);
  end;
  Result := not ACall.HasArguments or SameText(ACall.FirstArgument, 'nil') or ((mKind = TCreatedKind.Plain) and
    not MatchText(ACall.FirstArgument, ['Self', 'Owner', 'AOwner', 'Application']));
end;

procedure TCreateWithoutAssignmentScan.ReportCreate(ARoutine, AStatement: TSyntaxNode; const ACall: TCreateCall);
var
  mTypeText: string;
  mFix: TRuleFix;
  mFixes: TArray<TRuleFix>;
begin
  mTypeText := TextBetween(ACall.Position, ACall.After - 1);
  mFixes := nil;
  if AssignFix(ARoutine, AStatement, mTypeText, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(TTextRange.Create(Token(ACall.Position).StartPos, Token(ACall.Next - 1).EndPos),
    cTexts[TOwnershipText.Lost].Fmt([mTypeText]), mFixes);
end;

procedure TCreateWithoutAssignmentScan.CheckStatement(ARoutine, AStatement: TSyntaxNode);
var
  mCall: TCreateCall;
begin
  if CreateCallAt(AStatement, mCall) and IsLost(mCall) then
  begin
    ReportCreate(ARoutine, AStatement, mCall);
  end;
end;

procedure TCreateWithoutAssignmentScan.VisitStatements(ARoutine, ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.CallStatement then
      begin
        CheckStatement(ARoutine, mNode);
      end;
      // Lokale Routinen prüft Visit für sich.
      if (mNode <> ARoutine) and (mNode.Kind = TSyntaxKind.RoutineDecl) then
      begin
        Continue;
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

procedure TCreateWithoutAssignmentScan.Visit(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        VisitStatements(mNode, mNode);
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

procedure TCreateWithoutAssignmentScan.Run;
begin
  FSelfRegistering := TRuleOptions.Strings(FContext.Options, 'selfRegistering', nil);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  try
    Visit(FContext.Tree.Root);
  finally
    FreeAndNil(FAncestry);
  end;
end;

{ TSelfAsInterfaceScan }

/// <summary>Symbole der Datei und des Index mit dem Namen AName.</summary>
function TSelfAsInterfaceScan.SymbolsNamed(const AName: string): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  Result := nil;
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
  if FContext.Index <> nil then
  begin
    for mLocation in FContext.Index.FindSymbols(AName) do
    begin
      Result := Result + [mLocation.Symbol];
    end;
  end;
end;

/// <summary>Methode AMethod (z. B. _Release) als Rumpf in der Datei: 'TKlasse._Release'.</summary>
function TSelfAsInterfaceScan.MethodBody(const AClassName, AMethod: string): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (ANode.Kind = TSyntaxKind.RoutineDecl) and
        SameText(ANode.Name, AClassName + '.' + AMethod) and (TRoutineBody.BodyOf(ANode) <> nil) then
      begin
        mFound := ANode;
      end;
      Result := mFound = nil;
    end);
  Result := mFound;
end;

function TSelfAsInterfaceScan.Declares(const AClassName, AMethod: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if SameText(mSymbol.Container, AClassName) and SameText(mSymbol.Name, AMethod) and
      (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gibt _Release der Klasse das Objekt selbst frei (Destroy oder Free im Rumpf)?</summary>
function TSelfAsInterfaceScan.ReleaseFrees(const AClassName: string): Boolean;
var
  mRoutine: TSyntaxNode;
  mPosition: Integer;
begin
  Result := False;
  mRoutine := MethodBody(AClassName, '_Release');
  if mRoutine = nil then
  begin
    Exit;
  end;
  mPosition := CodeAt(mRoutine.StartOffset);
  while not Result and (mPosition <= High(FCode)) and (Token(mPosition).Offset < mRoutine.EndOffset) do
  begin
    Result := IsName(mPosition, 'Destroy') or IsName(mPosition, 'Free') or IsName(mPosition, 'FreeInstance');
    Inc(mPosition);
  end;
end;

/// <summary>Eigene Referenzzählung ohne Schutz in NewInstance: Eine Klasse der Kette gibt sich in _Release frei,
/// keine überschreibt NewInstance, die Kette reicht bis TObject.</summary>
function TSelfAsInterfaceScan.OwnCounting(const AClassName: string): Boolean;
var
  mCurrent: string;
  mSteps: Integer;
begin
  Result := False;
  mCurrent := AClassName;
  for mSteps := 1 to 32 do
  begin
    if SameText(mCurrent, 'TObject') then
    begin
      Exit;
    end;
    if (mCurrent = '') or SameText(mCurrent, 'TInterfacedObject') or Declares(mCurrent, 'NewInstance') then
    begin
      Exit(False);
    end;
    if Declares(mCurrent, '_Release') and ReleaseFrees(mCurrent) then
    begin
      Result := True;
    end;
    mCurrent := FAncestry.ParentOf(mCurrent);
  end;
  Result := False;
end;

/// <summary>Parametertyp an Stelle AIndex aller Routinen namens AName: True, wenn alle bekannten ein Interface
/// erwarten (Überladungen mit TObject an der Stelle machen den Fall unsicher).</summary>
function TSelfAsInterfaceScan.ExpectsInterface(const AName: string; AIndex: Integer): Boolean;
var
  mSymbol: TIndexSymbol;
  mKnown: Boolean;
begin
  mKnown := False;
  for mSymbol in SymbolsNamed(AName) do
  begin
    if not (mSymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) or
      (Length(mSymbol.ParamTypes) <= AIndex) then
    begin
      Continue;
    end;
    if not TSelfAsInterfaceInConstructorRule.IsInterfaceType(mSymbol.ParamTypes[AIndex]) then
    begin
      Exit(False);
    end;
    mKnown := True;
  end;
  Result := mKnown;
end;

/// <summary>Typ einer Variablen oder eines Feldes vor ":= Self".</summary>
function TSelfAsInterfaceScan.TargetIsInterface(APosition: Integer): Boolean;
var
  mTarget: Integer;
  mSymbol: TIndexSymbol;
  mTypeName: string;
begin
  mTarget := APosition - 2;
  if not IsWord(mTarget) or (IsSym(mTarget - 1, '.') and not IsName(mTarget - 2, 'Self')) then
  begin
    Exit(False);
  end;
  mTypeName := FTypes.DeclaredType(Token(mTarget).Text, Token(mTarget).StartPos);
  if mTypeName = '' then
  begin
    for mSymbol in FAncestry.Local.Symbols do
    begin
      if (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and
        SameText(mSymbol.Name, Token(mTarget).Text) then
      begin
        mTypeName := mSymbol.TypeName;
      end;
    end;
  end;
  Result := TSelfAsInterfaceInConstructorRule.IsInterfaceType(mTypeName);
end;

/// <summary>Self as IX mit Self bei APosition.</summary>
function TSelfAsInterfaceScan.IsAsInterface(APosition: Integer): Boolean;
begin
  Result := IsKey(APosition + 1, 'as') and IsWord(APosition + 2) and
    TSelfAsInterfaceInConstructorRule.IsInterfaceType(Token(APosition + 2).Text);
end;

/// <summary>IX(Self) mit Self bei APosition.</summary>
function TSelfAsInterfaceScan.IsInterfaceCast(APosition: Integer): Boolean;
begin
  Result := IsSym(APosition - 1, '(') and IsSym(APosition + 1, ')') and IsWord(APosition - 2) and
    TSelfAsInterfaceInConstructorRule.IsInterfaceType(Token(APosition - 2).Text);
end;

/// <summary>Endet bei APosition eine Anweisung (";", end, else)?</summary>
function TSelfAsInterfaceScan.IsStatementEnd(APosition: Integer): Boolean;
begin
  Result := IsSym(APosition, ';') or IsKey(APosition, 'end') or IsKey(APosition, 'else');
end;

/// <summary>Steht bei APosition ein ganzes Argument, zwischen "(" oder "," und ")" oder ","?</summary>
function TSelfAsInterfaceScan.IsArgument(APosition: Integer): Boolean;
begin
  Result := (IsSym(APosition - 1, '(') or IsSym(APosition - 1, ',')) and
    (IsSym(APosition + 1, ')') or IsSym(APosition + 1, ','));
end;

/// <summary>Öffnende Klammer des Aufrufs vor AStart und Stelle des Arguments; False in einer eckigen Klammer, nach
/// ";" oder ohne Klammer.</summary>
function TSelfAsInterfaceScan.CallOpening(AStart: Integer; out AOpen, AArgument: Integer): Boolean;
var
  mDepth: Integer;
  mToken: TPascalToken;
begin
  mDepth := 0;
  AArgument := 0;
  AOpen := AStart;
  while AOpen >= 0 do
  begin
    mToken := Token(AOpen);
    if mToken.IsSymbol(')') or mToken.IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if mToken.IsSymbol('[') or mToken.IsSymbol('(') then
    begin
      if mDepth = 0 then
      begin
        Exit(mToken.IsSymbol('('));
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and mToken.IsSymbol(',') then
    begin
      Inc(AArgument);
    end
    else if (mDepth = 0) and mToken.IsSymbol(';') then
    begin
      Exit(False);
    end;
    Dec(AOpen);
  end;
  Result := False;
end;

/// <summary>Erwartet die Routine, der Self bei APosition als Argument übergeben wird, an der Stelle ein
/// Interface?</summary>
function TSelfAsInterfaceScan.ArgumentExpectsInterface(APosition: Integer): Boolean;
var
  mOpen, mArgument: Integer;
begin
  Result := CallOpening(APosition - 1, mOpen, mArgument) and (mOpen >= 1) and IsWord(mOpen - 1);
  if Result then
  begin
    Result := ExpectsInterface(Token(mOpen - 1).Text, mArgument);
  end;
end;

/// <summary>Wird Self an APosition als Interface weitergegeben? Self as IX, IX(Self), Aufruf mit
/// Interface-Parameter oder Zuweisung an eine Interface-Variable.</summary>
function TSelfAsInterfaceScan.PassesAsInterface(APosition: Integer): Boolean;
begin
  if IsSym(APosition - 1, '.') or IsSym(APosition + 1, '.') then
  begin
    Result := False;
  end
  else if IsAsInterface(APosition) or IsInterfaceCast(APosition) then
  begin
    Result := True;
  end
  else if IsSym(APosition - 1, ':=') and IsStatementEnd(APosition + 1) then
  begin
    Result := TargetIsInterface(APosition);
  end
  else
  begin
    Result := IsArgument(APosition) and ArgumentExpectsInterface(APosition);
  end;
end;

/// <summary>Steht die Anweisung allein auf ihren Zeilen (davor nur Einrückung, danach nur ";")?</summary>
function TSelfAsInterfaceScan.OwnLines(AStatement: TSyntaxNode): Boolean;
var
  mRest: string;
begin
  mRest := Trim(Copy(FLines[AStatement.EndPos.Line], AStatement.EndPos.Character + 1, MaxInt));
  Result := (Trim(Copy(FLines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) = '') and
    ((mRest = '') or (mRest = ';')) and (AStatement.EndPos.Line < High(FLines));
end;

/// <summary>Korrektur: die Anweisung mit Self vor die Zeile mit inherited verschieben.</summary>
function TSelfAsInterfaceScan.MoveFix(ABlock: TSyntaxNode; AInherited, AOffset: Integer): TArray<TRuleFix>;
var
  mBefore, mMoved: TSyntaxNode;
  mLine: Integer;
  mText: string;
begin
  Result := nil;
  mBefore := TopStatement(ABlock, AInherited);
  mMoved := TopStatement(ABlock, AOffset);
  if (mBefore = nil) or (mMoved = nil) or (mBefore = mMoved) or not OwnLines(mBefore) or not OwnLines(mMoved) then
  begin
    Exit;
  end;
  mText := '';
  for mLine := mMoved.StartPos.Line to mMoved.EndPos.Line do
  begin
    mText := mText + FLines[mLine] + FLineBreak;
  end;
  Result := [TRuleFix.Create(cTexts[TOwnershipText.MoveBeforeInherited].Text, [
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(mBefore.StartPos.Line, 0),
      TTextPosition.Create(mBefore.StartPos.Line, 0)), mText),
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(mMoved.StartPos.Line, 0),
      TTextPosition.Create(mMoved.EndPos.Line + 1, 0)), '')])];
end;

/// <summary>Ist ARoutine ein Konstruktor bzw. AfterConstruction, in dem die Regel gilt? Fall 1: eigene
/// Referenzzählung; Fall 2: Nachfahren von TInterfacedObject nur in AfterConstruction nach inherited (der Schutz
/// ist dann aufgehoben).</summary>
function TSelfAsInterfaceScan.ConstructionRoutine(ARoutine: TSyntaxNode; out AInfo: TConstruction): Boolean;
var
  mFirst: Integer;
  mIsAfterConstruction: Boolean;
begin
  AInfo := Default(TConstruction);
  mFirst := CodeAt(ARoutine.StartOffset);
  if (Pos('.', ARoutine.Name) = 0) or IsKey(mFirst, 'class') then
  begin
    Exit(False);
  end;
  AInfo.TypeName := Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1);
  mIsAfterConstruction := SameText(Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt),
    'AfterConstruction');
  Result := IsKey(mFirst, 'constructor') or mIsAfterConstruction;
  if Result then
  begin
    AInfo.Block := TRoutineBody.BodyOf(ARoutine);
    Result := AInfo.Block <> nil;
  end;
  if Result then
  begin
    AInfo.Counting := OwnCounting(AInfo.TypeName);
    Result := AInfo.Counting or
      (mIsAfterConstruction and FAncestry.DescendsFrom(AInfo.TypeName, 'TInterfacedObject'));
  end;
  AInfo.Where := cTexts[TOwnershipText.InAfterConstruction].Text;
  if IsKey(mFirst, 'constructor') then
  begin
    AInfo.Where := cTexts[TOwnershipText.InConstructor].Text;
  end;
end;

procedure TSelfAsInterfaceScan.ReportSelf(const AInfo: TConstruction; APosition, AInheritedAt: Integer);
begin
  if AInfo.Counting then
  begin
    FReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      cTexts[TOwnershipText.SelfInterface].Fmt([AInfo.Where, AInfo.TypeName]));
  end
  else if AInheritedAt >= 0 then
  begin
    FReport.Add(TTextRange.Create(Token(APosition).StartPos, Token(APosition).EndPos),
      cTexts[TOwnershipText.SelfAfterConstruction].Text,
      MoveFix(AInfo.Block, Token(AInheritedAt).Offset, Token(APosition).Offset));
  end;
end;

procedure TSelfAsInterfaceScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mInfo: TConstruction;
  mPosition, mInheritedAt: Integer;
begin
  if not ConstructionRoutine(ARoutine, mInfo) then
  begin
    Exit;
  end;
  mInheritedAt := -1;
  mPosition := CodeAt(mInfo.Block.StartOffset);
  while (mPosition <= High(FCode)) and (Token(mPosition).Offset < mInfo.Block.EndOffset) do
  begin
    if (mInheritedAt < 0) and IsKey(mPosition, 'inherited') then
    begin
      mInheritedAt := mPosition;
    end;
    if IsName(mPosition, 'Self') and PassesAsInterface(mPosition) and
      (TRoutineBody.RoutineAt(FContext.Tree, Token(mPosition).Offset) = ARoutine) then
    begin
      ReportSelf(mInfo, mPosition, mInheritedAt);
    end;
    Inc(mPosition);
  end;
end;

procedure TSelfAsInterfaceScan.Run;
var
  mRoutines: TArray<TSyntaxNode>;
  mRoutine: TSyntaxNode;
begin
  mRoutines := nil;
  FContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mRoutines := mRoutines + [ANode];
      end;
      Result := True;
    end);
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
  FTypes := TDeclaredTypes.Create(FContext.Tree, FContext.Text);
  try
    for mRoutine in mRoutines do
    begin
      CheckRoutine(mRoutine);
    end;
  finally
    FreeAndNil(FTypes);
    FreeAndNil(FAncestry);
  end;
end;

{ TOwnedItemFreedRule }

function TOwnedItemFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOwnedItemFreedRuleId, TRuleSeverity.Error,
    cTexts[TOwnershipText.OwnedFreedTitle].Text);
end;

class function TOwnedItemFreedRule.CreatesOwning(const ATypeName, AArguments: string;
  out AIsDictionary: Boolean): Boolean;
begin
  AIsDictionary := ContainsText(ATypeName, 'TObjectDictionary');
  if AIsDictionary then
  begin
    Result := ContainsText(AArguments, 'doOwnsValues');
  end
  else
  begin
    Result := not TRegEx.IsMatch(AArguments, '\bFalse\b', [roIgnoreCase]);
  end;
end;

procedure TOwnedItemFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TOwnedItemFreedScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    (not ContainsText(AContext.Text, 'TObjectList') and not ContainsText(AContext.Text, 'TObjectDictionary')) then
  begin
    Exit;
  end;
  mScan := TOwnedItemFreedScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TCreateWithoutAssignmentRule }

function TCreateWithoutAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCreateWithoutAssignmentRuleId, TRuleSeverity.Warning,
    cTexts[TOwnershipText.LostTitle].Text);
end;

class function TCreateWithoutAssignmentRule.LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['T', 'E']) and CharInSet(AName[2], ['A'..'Z']);
end;

class function TCreateWithoutAssignmentRule.VariableName(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  if LooksLikeType(Result) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if Result = '' then
  begin
    Result := 'Objekt';
  end;
end;

procedure TCreateWithoutAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TCreateWithoutAssignmentScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Create') then
  begin
    Exit;
  end;
  mScan := TCreateWithoutAssignmentScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TSelfAsInterfaceInConstructorRule }

function TSelfAsInterfaceInConstructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cSelfAsInterfaceInConstructorRuleId, TRuleSeverity.Warning,
    cTexts[TOwnershipText.SelfInterfaceTitle].Text);
end;

class function TSelfAsInterfaceInConstructorRule.IsInterfaceType(const AType: string): Boolean;
var
  mName: string;
begin
  mName := Trim(AType);
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  Result := (Length(mName) >= 2) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

procedure TSelfAsInterfaceInConstructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TSelfAsInterfaceScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Self') then
  begin
    Exit;
  end;
  mScan := TSelfAsInterfaceScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterOwnershipRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedItemFreedRule.Create);
  ARegistry.Register(TCreateWithoutAssignmentRule.Create);
  ARegistry.Register(TSelfAsInterfaceInConstructorRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Ownership', cTexts);

end.
