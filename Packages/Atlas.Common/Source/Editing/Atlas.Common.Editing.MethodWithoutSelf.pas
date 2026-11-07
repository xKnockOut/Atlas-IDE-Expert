unit Atlas.Common.Editing.MethodWithoutSelf;

// Methode ohne Self umwandeln (#686):
//   Erkennung: eine Instanzmethode einer Klasse oder eines Records, deren
//     Rumpf in der Unit steht und die weder Self noch ein Instanzmitglied
//     (Feld, Property, Instanzmethode, Konstruktor, auch ohne Self. davor)
//     noch inherited oder with benutzt. Nicht virtual, dynamic, override,
//     abstract, message, reintroduce oder final, nicht überladen, kein
//     Konstruktor, Destruktor oder Operator, keine Zugriffsmethode einer
//     Property, nicht Teil eines Interfaces der Klasse (Vorfahrenliste oder
//     Methodenzuordnung), nicht in der Formulardatei als Ereignis und in den
//     Methoden der Klasse nicht als Methodenzeiger benutzt. Ob Namen
//     Instanzmitglieder sind, sagt TMethodLookup (Namensauflösung, sonst die
//     Klasse in der Datei); unbekannte Namen verhindern die Erkennung.
//   In class-Methode umwandeln: class davor, mit refactoring.methodKindStatic
//     auch static (Records immer). Braucht der Rumpf Klassenmethoden ohne
//     static, bleibt static weg (Warnung). Aufrufe über Instanzen bleiben
//     gültig; die zweite Aktion stellt Aufrufe über eine Variablenkette
//     (K.X, Liste[I].X) auf die Klasse um.
//   In freie Routine umwandeln: Deklaration aus der Klasse entfernen, Kopf
//     ohne Klasse; ins interface, wenn die Klasse dort steht und andere Units
//     die Methode aufrufen, sonst nur in implementation (vor die erste
//     Routine der Unit, die sie aufruft). Klassenmitglieder im Rumpf (class
//     var, Konstanten, Typen, class-Methoden) bekommen die Klasse davor;
//     strict private bzw. strict protected verhindern das. Aufrufe verlieren
//     den Objektbezug (Warnung, wenn der weggefallene Ausdruck mehr als eine
//     Variablenkette war), andere Units bekommen die Unit ins uses (#284) und
//     rufen sie qualifiziert auf, wenn sie selbst einen gleichnamigen Namen
//     deklarieren.
//   In Record-Helper verschieben: wenn der erste Parameter einen einfachen
//     Typ hat (string, Integer, TDateTime …), nicht var/out, ohne Vorgabewert
//     und im Rumpf nicht geschrieben wird. Die Methode wandert in einen
//     vorhandenen record helper der Unit für den Typ oder einen neuen
//     T<Typ>Helper (im interface nur, wenn andere Units aufrufen), der
//     Parameter wird Self, Aufrufe werden S.X(Rest) bzw. (Ausdruck).X(Rest).
//     Ist für den Typ schon ein anderer Helper sichtbar, warnt Atlas: Nur ein
//     Helper je Typ wirkt.
// Die Verwendungen in allen Dateien liefert der Aufrufer (Referenzsuche);
// jede Datei muss danach fehlerfrei parsen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup;

type
{$SCOPEDENUMS ON}
  /// <summary>Umwandlung: class-Methode, class-Methode samt Aufrufen über die Klasse, freie Routine, Helper.</summary>
  TMethodConversion = (ClassMethod, ClassMethodCalls, Routine, Helper);
  /// <summary>Verwendung der Methode an einer Stelle.</summary>
  TMethodUse = (Call, Value, Pointer, Inherited_, Accessor, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Methode ohne Self.</summary>
  TMethodTarget = record
    ClassName: string;
    Name: string;
    IsRecord: Boolean;
    /// <summary>Name im Kopf der Implementierung (Start der Referenzsuche).</summary>
    NamePosition: TTextPosition;
    /// <summary>Ende des Kopfs der Implementierung (Marke).</summary>
    HeaderEnd: TTextPosition;
    /// <summary>Warum keine freie Routine bzw. kein Helper geht; '' = geht.</summary>
    RoutineReason: string;
    HelperReason: string;
    /// <summary>Typ des ersten Parameters, wenn der Helper geht.</summary>
    HelperType: string;
    function Conversions: TArray<TMethodConversion>;
    function Title(AConversion: TMethodConversion): string;
  end;

  /// <summary>Eine Datei mit Verwendungen der Methode.</summary>
  TMethodSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    /// <summary>Anfang des Namens je Verwendung (ohne Deklaration und Kopf); 0-basierte Offsets.</summary>
    Offsets: TArray<Integer>;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree;
      const AOffsets: TArray<Integer>): TMethodSource; static;
  end;

  /// <summary>Gewünschte Umwandlung der Methode, deren Kopf APosition enthält; AWithStatic:
  /// refactoring.methodKindStatic.</summary>
  TMethodRequest = record
    Position: TTextPosition;
    Conversion: TMethodConversion;
    WithStatic: Boolean;
    Lookup: TMethodLookup;
    Style: TFormatStyle;
    class function Create(const APosition: TTextPosition; AConversion: TMethodConversion; AWithStatic: Boolean;
      const ALookup: TMethodLookup; const AStyle: TFormatStyle): TMethodRequest; static;
  end;

  TMethodFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TMethodResult = record
    Files: TArray<TMethodFileEdits>;
    Warnings: TArray<string>;
    /// <summary>Geänderte Aufrufe.</summary>
    Calls: Integer;
    /// <summary>Was geschieht, dazu je geänderter Aufruf "Datei, Zeile n: alt → neu".</summary>
    Preview: string;
  end;

  TMethodWithoutSelf = class
  public const
    /// <summary>Text der Marke für Clients; das Plugin beschriftet sie selbst in der Sprache der IDE.</summary>
    cMarkerText = 'Self unused';
  public
    class function ClassMethodTitle: string; static;
    class function ClassMethodCallsTitle: string; static;
    class function RoutineTitle: string; static;
    class function HelperTitle: string; static;
    /// <summary>Methode ohne Self, deren Kopf (Implementierung oder Deklaration) APosition enthält.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TMethodLookup; out ATarget: TMethodTarget; out AReason: string): Boolean; static;
    /// <summary>Alle Methoden ohne Self der Datei (Marke, Hinweis).</summary>
    class function Candidates(const AText: string; ATree: TSyntaxTree;
      const ALookup: TMethodLookup): TArray<TMethodTarget>; static;
    /// <summary>Verwendung des Namens AName, der an AOffset beginnt; ACall: der Aufruf mit Argumenten oder nil.
    /// </summary>
    class function UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string; out ACallee,
      ACall: TSyntaxNode): TMethodUse; static;
    /// <summary>Wandelt die Methode in ADeclaring um, wie ARequest sagt; AOthers: weitere Dateien mit
    /// Verwendungen.</summary>
    class function Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
      const ARequest: TMethodRequest; out AResult: TMethodResult; out AReason: string): Boolean; static;
    /// <summary>Name der Umwandlung für Befehlsargumente: classMethod, classMethodCalls, routine, helper.</summary>
    class function ConversionName(AConversion: TMethodConversion): string; static;
    class function ConversionOf(const AName: string; out AConversion: TMethodConversion): Boolean; static;
    /// <summary>Einfacher Typ für einen Record-Helper?</summary>
    class function IsSimpleType(const ATypeName: string): Boolean; static;
    /// <summary>Name eines neuen Helpers: TStringHelper, TDateTimeHelper.</summary>
    class function HelperNameFor(const ATypeName: string): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.MethodWithoutSelf.Texts,
  Atlas.Common.Localization.Texts;

class function TMethodWithoutSelf.ClassMethodTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethod].Text;
end;

class function TMethodWithoutSelf.ClassMethodCallsTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethodCalls].Text;
end;

class function TMethodWithoutSelf.RoutineTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToStandaloneRoutine].Text;
end;

class function TMethodWithoutSelf.HelperTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.MoveToRecordHelperFor].Text;
end;

const
  cSimpleTypes: array[0..27] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char',
    'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Currency', 'Boolean',
    'TDateTime', 'TDate', 'TTime', 'TGUID');
  // Direktiven, die an einer freien Routine bzw. einem Helper nicht passen.
  cDroppedDirectives: array[0..8] of string = ('overload', 'reintroduce', 'final', 'static', 'virtual', 'dynamic',
    'override', 'abstract', 'message');

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

function SameTypeName(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or (MatchText(A, ['string', 'UnicodeString']) and MatchText(B, ['string',
    'UnicodeString']));
end;

function Where(const AFileName: string; ALine: Integer): string;
begin
  if AFileName = '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Line].Fmt([ALine + 1]);
  end
  else
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Line2].Fmt([ExtractFileName(AFileName), ALine + 1]);
  end;
end;

{ TMethodTarget }

function TMethodTarget.Conversions: TArray<TMethodConversion>;
begin
  Result := [TMethodConversion.ClassMethod, TMethodConversion.ClassMethodCalls];
  if RoutineReason = '' then
  begin
    Result := Result + [TMethodConversion.Routine];
  end;
  if HelperReason = '' then
  begin
    Result := Result + [TMethodConversion.Helper];
  end;
end;

function TMethodTarget.Title(AConversion: TMethodConversion): string;
begin
  case AConversion of
    TMethodConversion.ClassMethodCalls:
      Result := Format(TMethodWithoutSelf.ClassMethodCallsTitle, [ClassName]);
    TMethodConversion.Routine:
      Result := TMethodWithoutSelf.RoutineTitle;
    TMethodConversion.Helper:
      Result := Format(TMethodWithoutSelf.HelperTitle, [HelperType]);
  else
    Result := TMethodWithoutSelf.ClassMethodTitle;
  end;
end;

{ TMethodSource }

class function TMethodSource.Create(const AFileName, AText: string; ATree: TSyntaxTree;
  const AOffsets: TArray<Integer>): TMethodSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Offsets := AOffsets;
end;

{ TMethodRequest }

class function TMethodRequest.Create(const APosition: TTextPosition; AConversion: TMethodConversion;
  AWithStatic: Boolean; const ALookup: TMethodLookup; const AStyle: TFormatStyle): TMethodRequest;
begin
  Result.Position := APosition;
  Result.Conversion := AConversion;
  Result.WithStatic := AWithStatic;
  Result.Lookup := ALookup;
  Result.Style := AStyle;
end;

type
  /// <summary>Analyse der Methode in ihrer Unit.</summary>
  TMethodPlan = class
  public
    Text: string;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    Lines: TLineTable;
    Lookup: TMethodLookup;
    Cache: TLocalsCache;
    Routine: TSyntaxNode;
    Header: TSyntaxNode;
    Body: TSyntaxNode;
    Declaration: TSyntaxNode;
    TypeBody: TSyntaxNode;
    Target: TMethodTarget;
    Visibility: string;
    ClassInInterface: Boolean;
    IsFunction: Boolean;
    Parameters: TArray<TParameterText>;
    /// <summary>Namen im Rumpf und im Kopf, die ohne Klasse die Klasse davor brauchen.</summary>
    Statics: TArray<TSyntaxNode>;
    /// <summary>Kopf der Deklaration nennt einen Typ der Klasse.</summary>
    HeadUsesClassType: Boolean;
    UsesClassLevel: Boolean;
    StrictName: string;
    constructor Create(const AText: string; ATree: TSyntaxTree; const ALookup: TMethodLookup);
    destructor Destroy; override;
    function Analyze(AOffset: Integer; out AReason: string): Boolean;
    /// <summary>Virtuell, Teil eines Interfaces, Zugriffsmethode oder Ereignis der Formulardatei?</summary>
    function DeclarationIssue: string;
    /// <summary>Stehen Attribute ([Test]) direkt vor der Deklaration?</summary>
    function HasAttributes: Boolean;
    /// <summary>Namen im Rumpf: Self, inherited, with und Instanzmitglieder verhindern die Umwandlung.</summary>
    function NamesIssue: string;
    function NameIssue(ANode: TSyntaxNode): string;
    procedure NoteStatic(ANode: TSyntaxNode; ALevel: TMemberLevel; AVisible: TIndexVisibility; AInHead: Boolean);
    /// <summary>Methodenzeiger in den Methoden der Klasse.</summary>
    function LocalUsesIssue: string;
    procedure CheckRoutine;
    procedure CheckHelper;
    function UnitName: string;
    /// <summary>Als Methodenzeiger benutzt: @X, bei Prozeduren und Funktionen mit Parametern jede Verwendung als
    /// Wert.</summary>
    function IsPointer(AUse: TMethodUse): Boolean;
    /// <summary>Wird der erste Parameter im Rumpf geschrieben oder in einer anonymen Methode benutzt?</summary>
    function FirstParameterUses(out AReason: string): Boolean;
    /// <summary>Bezeichner im Rumpf, die den ersten Parameter meinen.</summary>
    function FirstParameterNodes: TArray<TSyntaxNode>;
  end;

constructor TMethodPlan.Create(const AText: string; ATree: TSyntaxTree; const ALookup: TMethodLookup);
begin
  inherited Create;
  Text := AText;
  Tree := ATree;
  Tokens := ATree.Tokens;
  Lines := TLineTable.Build(AText);
  Lookup := ALookup;
  Cache := TLocalsCache.Create(AText, ATree);
end;

destructor TMethodPlan.Destroy;
begin
  Cache.Free;
  inherited;
end;

function TMethodPlan.UnitName: string;
begin
  Result := Tree.Root.Name;
end;

function TMethodPlan.IsPointer(AUse: TMethodUse): Boolean;
begin
  Result := (AUse = TMethodUse.Pointer) or ((AUse = TMethodUse.Value) and (not IsFunction or (Parameters <> nil)));
end;

function ClassNameIssue(const AClassName: string): string;
begin
  Result := '';
  if AClassName = '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.NoMethod].Text;
  end
  else if (Pos('<', AClassName) > 0) or (Pos('.', AClassName) > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.MethodOfAGenericOr].Text;
  end;
end;

/// <summary>Methode mit Rumpf im implementation-Teil an AOffset.</summary>
function RoutineIssue(APlan: TMethodPlan; AOffset: Integer): string;
begin
  if (APlan.Tree = nil) or (APlan.Tree.Root = nil) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NoTree].Text);
  end;
  APlan.Routine := TRoutineParts.TopRoutineAt(APlan.Tree, AOffset, APlan.Declaration);
  if (APlan.Routine = nil) or (APlan.Routine.Parent = nil) or
    (APlan.Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NoMethodWithABody].Text);
  end;
  APlan.Header := TRoutineParts.HeaderOf(APlan.Routine);
  APlan.Body := TRoutineBody.BodyOf(APlan.Routine);
  if (APlan.Header = nil) or (APlan.Body = nil) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.MethodWithoutBody].Text);
  end;
  APlan.Target.Name := TRoutineBody.ShortNameOf(APlan.Routine.Name);
  APlan.Target.ClassName := TRoutineBody.QualifierOf(APlan.Routine.Name);
  Result := ClassNameIssue(APlan.Target.ClassName);
end;

function IsSpecialRoutine(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, AHeader.StartOffset);
  Result := (mIndex <= High(ATokens)) and (ATokens[mIndex].IsKeyword('constructor') or
    ATokens[mIndex].IsKeyword('destructor') or ATokens[mIndex].IsKeyword('operator'));
end;

function HeaderIssue(APlan: TMethodPlan): string;
begin
  Result := '';
  if IsSpecialRoutine(APlan.Tokens, APlan.Header) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.ConstructorDestructorOrOperator].Text;
  end
  else if TRoutineParts.IsClassHeader(APlan.Tokens, APlan.Header) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.AlreadyAClassMethod].Text;
  end
  else if TRoutineParts.HasWord(APlan.Tokens, APlan.Header, ['forward', 'external', 'assembler']) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UnsupportedForm].Text;
  end;
end;

/// <summary>Anzahl der Deklarationen namens AName im Typrumpf (ohne Methodenzuordnungen); ADeclaration: die
/// letzte.</summary>
function DeclarationsOf(ATypeBody: TSyntaxNode; const AName: string; out ADeclaration: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  ADeclaration := nil;
  for mIndex := 0 to ATypeBody.ChildCount - 1 do
  begin
    if (ATypeBody[mIndex].Kind = TSyntaxKind.RoutineHeader) and not ATypeBody[mIndex].IsMethodResolution and
      SameText(ATypeBody[mIndex].Name, AName) then
    begin
      Inc(Result);
      ADeclaration := ATypeBody[mIndex];
    end;
  end;
end;

/// <summary>Klasse in der Datei und genau eine Deklaration der Methode.</summary>
function TypeIssue(APlan: TMethodPlan): string;
var
  mFound: Integer;
begin
  Result := '';
  APlan.TypeBody := TRoutineBody.TypeBody(APlan.Tree.Root, APlan.Target.ClassName);
  if (APlan.TypeBody = nil) or not (APlan.TypeBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.ClassNotInTheFile].Fmt([APlan.Target.ClassName]));
  end;
  APlan.Target.IsRecord := APlan.TypeBody.Kind = TSyntaxKind.RecordType;
  mFound := DeclarationsOf(APlan.TypeBody, APlan.Target.Name, APlan.Declaration);
  if mFound > 1 then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.Overloaded].Text;
  end
  else if APlan.Declaration = nil then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.DeclarationMissing].Text;
  end;
end;

/// <summary>Sichtbarkeit, Lage der Klasse, Art und Parameter der Methode.</summary>
function SignatureIssue(APlan: TMethodPlan): string;
var
  mSection, mParameters: TSyntaxNode;
begin
  Result := '';
  APlan.Visibility := TRoutineBody.VisibilityOf(APlan.TypeBody, APlan.Declaration);
  mSection := APlan.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  APlan.ClassInInterface := (mSection <> nil) and TRoutineBody.Within(APlan.TypeBody, mSection);
  APlan.IsFunction := TRoutineParts.IsFunction(APlan.Routine);
  APlan.Parameters := TRoutineParts.ParameterTexts(APlan.Text, APlan.Declaration);
  mParameters := APlan.Declaration.FindChild(TSyntaxKind.Parameters);
  if (APlan.Parameters = nil) and (mParameters <> nil) and (mParameters.ChildCount > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UnsupportedParameters].Text;
  end;
end;

function NamePositionIssue(APlan: TMethodPlan): string;
var
  mFirst, mLast: Integer;
begin
  Result := '';
  if not TRoutineParts.NameTokens(APlan.Tokens, APlan.Header, mFirst, mLast) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NameNotFoundInThe].Text);
  end;
  APlan.Target.NamePosition := APlan.Tokens[mLast].StartPos;
  APlan.Target.HeaderEnd := APlan.Header.EndPos;
end;

function TMethodPlan.Analyze(AOffset: Integer; out AReason: string): Boolean;
begin
  AReason := RoutineIssue(Self, AOffset);
  if AReason = '' then
  begin
    AReason := HeaderIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := TypeIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := SignatureIssue(Self);
  end;
  if AReason = '' then
  begin
    AReason := DeclarationIssue;
  end;
  if AReason = '' then
  begin
    AReason := NamesIssue;
  end;
  if AReason = '' then
  begin
    AReason := LocalUsesIssue;
  end;
  if AReason = '' then
  begin
    AReason := NamePositionIssue(Self);
  end;
  Result := AReason = '';
  if Result then
  begin
    CheckRoutine;
    CheckHelper;
  end;
end;

/// <summary>Nennt die Property ANode AName hinter read, write oder stored?</summary>
function IsAccessorOf(const ATokens: TArray<TPascalToken>; AProperty: TSyntaxNode; const AName: string): Boolean;
var
  mToken: Integer;
  mInClause: Boolean;
begin
  mInClause := False;
  mToken := TRoutineBody.TokenAt(ATokens, AProperty.StartOffset);
  while (mToken <= High(ATokens)) and (ATokens[mToken].Offset < AProperty.EndOffset) do
  begin
    if MatchText(ATokens[mToken].Text, ['read', 'write', 'stored']) then
    begin
      mInClause := True;
    end
    else if mInClause and SameText(ATokens[mToken].Text, AName) then
    begin
      Exit(True);
    end;
    Inc(mToken);
  end;
  Result := False;
end;

/// <summary>Bindet ein Element des Typrumpfs die Methode (Methodenzuordnung, Interface, Property)?</summary>
function MemberIssue(APlan: TMethodPlan; AChild: TSyntaxNode): string;
begin
  Result := '';
  // Methodenzuordnung "procedure IFoo.Bar = Name".
  if (AChild.Kind = TSyntaxKind.RoutineHeader) and AChild.IsMethodResolution and
    SameText(AChild.ResolutionTarget, APlan.Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.MethodOfAnInterface].Fmt([AChild.Name]);
  end
  // Vorfahrenliste: Interfaces, deren Mitglied die Methode ist.
  else if (AChild.Kind = TSyntaxKind.TypeReference) and Assigned(APlan.Lookup.InterfaceMember) and
    APlan.Lookup.InterfaceMember(AChild.Name, APlan.Target.Name, AChild.StartOffset) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.BelongsToTheInterface].Text + AChild.Name;
  end
  else if (AChild.Kind = TSyntaxKind.PropertyDecl) and IsAccessorOf(APlan.Tokens, AChild, APlan.Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.AccessorOfTheProperty].Text + AChild.Name;
  end;
end;

function TMethodPlan.HasAttributes: Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.PreviousToken(Tokens, TRoutineBody.TokenAt(Tokens, Declaration.StartOffset));
  Result := (mIndex >= 0) and Tokens[mIndex].IsSymbol(']');
end;

function TMethodPlan.DeclarationIssue: string;
var
  mIndex: Integer;
begin
  if TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message',
    'reintroduce', 'final']) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.VirtualOverrideOrMessage].Text);
  end;
  // Attribute ([Test], [Setup] …) und published: Aufruf über RTTI an der Instanz (DUnitX, MethodAddress).
  if HasAttributes or SameText(Visibility, 'published') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.CalledViaRtti].Text);
  end;
  for mIndex := 0 to TypeBody.ChildCount - 1 do
  begin
    Result := MemberIssue(Self, TypeBody[mIndex]);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  Result := '';
  if Assigned(Lookup.InForm) and Lookup.InForm(Target.Name) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.IsAnEventInThe].Text;
  end;
end;

/// <summary>Kommt das Schlüsselwort AKeyword in ARoutine vor?</summary>
function HasKeyword(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode; const AKeyword: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ARoutine.EndOffset) do
  begin
    if ATokens[mIndex].IsKeyword(AKeyword) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

function TMethodPlan.NamesIssue: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Statics := nil;
  if not Assigned(Lookup.MemberLevel) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.NamesCannotBeResolved].Text);
  end;
  if HasKeyword(Tokens, Routine, 'inherited') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesInherited].Text);
  end;
  Result := '';
  if TRoutineLocals.HasKind(Routine, TSyntaxKind.WithStatement) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesWith].Text);
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.Identifier, mNodes);
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, mNodes);
    // Typen im Kopf der Deklaration gelten in der Klasse.
    TRoutineLocals.CollectKind(Declaration, TSyntaxKind.TypeReference, mNodes);
    for mNode in mNodes do
    begin
      Result := NameIssue(mNode);
      if Result <> '' then
      begin
        Break;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Namen, die nichts über die Klasse sagen: Typen im Kopf der Implementierung, qualifizierte Typen,
/// lokal verdeckte Namen.</summary>
function IsNeutralName(APlan: TMethodPlan; ANode: TSyntaxNode; AInHead: Boolean): Boolean;
begin
  if ANode.Kind = TSyntaxKind.TypeReference then
  begin
    if TRoutineBody.Within(ANode, APlan.Header) or (Pos('.', ANode.Name) > 0) then
    begin
      Exit(True);
    end;
  end;
  Result := not AInHead and TRoutineParts.Shadowed(APlan.Cache, ANode, APlan.Routine,
    TMethodLookup.HeadName(ANode.Name), True);
end;

/// <summary>Art des Namens; ein Typname ist nie ein Instanzmitglied, unbekannte Typen ändern nichts.</summary>
function NodeLevel(APlan: TMethodPlan; ANode: TSyntaxNode; out AVisible: TIndexVisibility): TMemberLevel;
begin
  Result := APlan.Lookup.MemberLevel(ANode, AVisible);
  if (ANode.Kind = TSyntaxKind.TypeReference) and (Result in [TMemberLevel.Instance, TMemberLevel.Unknown]) then
  begin
    Result := TMemberLevel.NotMember;
  end;
end;

function TMethodPlan.NameIssue(ANode: TSyntaxNode): string;
var
  mInHead: Boolean;
  mLevel: TMemberLevel;
  mVisible: TIndexVisibility;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self') then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsesSelf].Fmt([Where('', ANode.StartPos.Line)]));
  end;
  mInHead := TRoutineBody.Within(ANode, Declaration) or TRoutineBody.Within(ANode, Header);
  if IsNeutralName(Self, ANode, mInHead) then
  begin
    Exit;
  end;
  mLevel := NodeLevel(Self, ANode, mVisible);
  case mLevel of
    TMemberLevel.Instance:
      Result := cTexts[TEditingMethodWithoutSelfText.UsesText].Fmt([ANode.Name, Where('', ANode.StartPos.Line)]);
    TMemberLevel.Unknown:
      Result := cTexts[TEditingMethodWithoutSelfText.IsUnknown].Fmt([TMethodLookup.HeadName(ANode.Name),
        Where('', ANode.StartPos.Line)]);
    TMemberLevel.ClassLevel, TMemberLevel.StaticLevel:
      NoteStatic(ANode, mLevel, mVisible, mInHead);
    TMemberLevel.NotMember: ;
  end;
end;

procedure TMethodPlan.NoteStatic(ANode: TSyntaxNode; ALevel: TMemberLevel; AVisible: TIndexVisibility;
  AInHead: Boolean);
begin
  if ALevel = TMemberLevel.ClassLevel then
  begin
    UsesClassLevel := True;
  end;
  if AInHead then
  begin
    HeadUsesClassType := True;
  end
  else
  begin
    Statics := Statics + [ANode];
  end;
  if (StrictName = '') and (AVisible in [TIndexVisibility.StrictPrivate, TIndexVisibility.StrictProtected]) then
  begin
    StrictName := TMethodLookup.HeadName(ANode.Name);
  end;
end;

/// <summary>Benutzt die Methode AOther der Klasse die Methode als Methodenzeiger?</summary>
function PointerUseIssue(APlan: TMethodPlan; AOther: TSyntaxNode): string;
var
  mUses: TList<TSyntaxNode>;
  mNode, mCallee, mCall: TSyntaxNode;
begin
  Result := '';
  mUses := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(AOther, TSyntaxKind.Identifier, mUses);
    for mNode in mUses do
    begin
      if SameText(mNode.Name, APlan.Target.Name) and not TRoutineBody.Within(mNode, TRoutineParts.HeaderOf(AOther))
        and APlan.IsPointer(TMethodWithoutSelf.UseAt(APlan.Tree, mNode.StartOffset, APlan.Target.Name, mCallee,
        mCall)) then
      begin
        Exit(cTexts[TEditingMethodWithoutSelfText.IsUsedAsAMethod].Fmt([Where('', mNode.StartPos.Line)]));
      end;
    end;
  finally
    mUses.Free;
  end;
end;

function TMethodPlan.LocalUsesIssue: string;
var
  mIndex: Integer;
  mOther: TSyntaxNode;
begin
  // In den Methoden der Klasse: Methodenzeiger ohne Self. davor (OnClick := Name) sieht schon die Datei.
  Result := '';
  for mIndex := 0 to Routine.Parent.ChildCount - 1 do
  begin
    mOther := Routine.Parent[mIndex];
    if (mOther.Kind = TSyntaxKind.RoutineDecl) and SameText(TRoutineBody.QualifierOf(mOther.Name),
      Target.ClassName) then
    begin
      Result := PointerUseIssue(Self, mOther);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Was in der Klasse bleiben muss: strict-Mitglieder oder Typen der Klasse im Kopf.</summary>
function ClassBoundIssue(APlan: TMethodPlan): string;
begin
  Result := '';
  if APlan.StrictName <> '' then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.UsesStrict].Fmt([APlan.StrictName]);
  end
  else if APlan.HeadUsesClassType then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.TheHeaderNamesAType].Text;
  end;
end;

procedure TMethodPlan.CheckRoutine;
begin
  Target.RoutineReason := ClassBoundIssue(Self);
  if (Target.RoutineReason = '') and (IndexText(Target.Name, TRoutineParts.UnitNames(Tree.Root)) >= 0) then
  begin
    Target.RoutineReason := Target.Name + cTexts[TEditingMethodWithoutSelfText.AlreadyExistsInTheUnit].Text;
  end;
end;

function TMethodPlan.FirstParameterNodes: TArray<TSyntaxNode>;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := nil;
  if Parameters = nil then
  begin
    Exit;
  end;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, Parameters[0].Name) and not TRoutineParts.Shadowed(Cache, mNode, Routine,
        Parameters[0].Name, False) then
      begin
        Result := Result + [mNode];
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TMethodPlan.FirstParameterUses(out AReason: string): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  AReason := '';
  for mNode in FirstParameterNodes do
  begin
    // const schreibt der Compiler ohnehin nicht; ein Wertparameter würde als Self den Wert des Aufrufers ändern.
    if (Parameters[0].Modifier = '') and (TRoutineLocals.AccessOf(mNode, Lookup.Flow) <> TLocalAccess.Read) then
    begin
      Exit(not Fail(Parameters[0].Name + cTexts[TEditingMethodWithoutSelfText.IsWritten].Text, AReason));
    end;
    if (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.AddressOf) then
    begin
      Exit(not Fail('@' + Parameters[0].Name, AReason));
    end;
    if TRoutineParts.InAnonymous(mNode, Routine) then
    begin
      Exit(not Fail(Parameters[0].Name + cTexts[TEditingMethodWithoutSelfText.InAnAnonymousMethod].Text, AReason));
    end;
  end;
end;

/// <summary>Taugt der erste Parameter als Self eines Helpers (ohne var/out, mit Typ, ohne Vorgabewert)?</summary>
function FirstParameterIssue(const AParameters: TArray<TParameterText>): string;
begin
  Result := '';
  if AParameters = nil then
  begin
    Result := 'ohne Parameter';
  end
  else if not MatchText(AParameters[0].Modifier, ['', 'const']) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.FirstParameterIs].Text + AParameters[0].Modifier;
  end
  else if (AParameters[0].Rest = '') or (Pos('=', AParameters[0].Rest) > 0) then
  begin
    Result := cTexts[TEditingMethodWithoutSelfText.FirstParameterWithoutTypeOr].Text;
  end;
end;

function HelperIssue(APlan: TMethodPlan; out ATypeName: string): string;
begin
  ATypeName := '';
  Result := ClassBoundIssue(APlan);
  if Result = '' then
  begin
    Result := FirstParameterIssue(APlan.Parameters);
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  ATypeName := Trim(Copy(APlan.Parameters[0].Rest, 3, MaxInt));
  if not TMethodWithoutSelf.IsSimpleType(ATypeName) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.FirstParameterHasNoSimple].Text);
  end;
  APlan.FirstParameterUses(Result);
end;

procedure TMethodPlan.CheckHelper;
var
  mTypeName: string;
begin
  Target.HelperType := '';
  Target.HelperReason := HelperIssue(Self, mTypeName);
  if Target.HelperReason = '' then
  begin
    Target.HelperType := mTypeName;
  end;
end;

{ Umwandlung }

type
  /// <summary>Bearbeitungen einer Datei in Offsets.</summary>
  TFileWork = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Lines: TLineTable;
    Edits: TArray<TOffsetEdit>;
    Offsets: TArray<Integer>;
    Declaring: Boolean;
    /// <summary>Unit des Aufrufers braucht die Unit der Methode im uses.</summary>
    NeedsUses: Boolean;
    /// <summary>Eigene Namen auf Unit-Ebene (gleichnamige Routine verdeckt die neue).</summary>
    Names: TArray<string>;
    constructor Create(const ASource: TMethodSource; ADeclaring: Boolean);
  end;

constructor TFileWork.Create(const ASource: TMethodSource; ADeclaring: Boolean);
begin
  inherited Create;
  FileName := ASource.FileName;
  Text := ASource.Text;
  Tree := ASource.Tree;
  Lines := TLineTable.Build(Text);
  Offsets := ASource.Offsets;
  Declaring := ADeclaring;
  if Tree <> nil then
  begin
    Names := TRoutineParts.UnitNames(Tree.Root);
  end;
end;

/// <summary>Bearbeitung, die ANode samt Zeile entfernt, wenn die Zeile sonst leer ist; sonst nur den Bereich.</summary>
function RemoveLine(const AText: string; const ALines: TLineTable; ANode: TSyntaxNode): TOffsetEdit;
var
  mLineStart, mNextStart: Integer;
begin
  mLineStart := ALines.LineStart(ANode.StartPos.Line);
  mNextStart := ALines.LineStart(ANode.EndPos.Line + 1);
  if ANode.EndPos.Line + 1 >= ALines.LineCount then
  begin
    mNextStart := Length(AText);
  end;
  if (Trim(Copy(AText, mLineStart + 1, ANode.StartOffset - mLineStart)) = '') and
    (Trim(Copy(AText, ANode.EndOffset + 1, mNextStart - ANode.EndOffset)) = '') then
  begin
    Result := TOffsetEdit.Create(mLineStart, mNextStart, '');
  end
  else
  begin
    Result := TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, '');
  end;
end;

/// <summary>Direktiven der Deklaration, die mitkommen ("inline; stdcall;"), mit führendem Leerzeichen.</summary>
function KeptDirectives(const AText: string; ADeclaration: TSyntaxNode): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ADeclaration.ChildCount - 1 do
  begin
    mChild := ADeclaration[mIndex];
    if (mChild.Kind = TSyntaxKind.Directive) and (IndexText(mChild.Name, cDroppedDirectives) < 0) then
    begin
      Result := Result + ' ' + TRoutineBody.TextOf(AText, mChild) + ';';
    end;
  end;
end;

/// <summary>Einrückung der Zeile ALine.</summary>
function IndentAt(const AText: string; const ALines: TLineTable; ALine: Integer): string;
begin
  Result := TTextLines.IndentOf(Copy(AText, ALines.LineStart(ALine) + 1, ALines.LineContentEnd(ALine) -
    ALines.LineStart(ALine)));
end;

/// <summary>Zeile ALine ohne Umbruch.</summary>
function LineText(const AText: string; const ALines: TLineTable; ALine: Integer): string;
begin
  Result := Copy(AText, ALines.LineStart(ALine) + 1, ALines.LineContentEnd(ALine) - ALines.LineStart(ALine));
end;

type
  TMethodBuild = class
  public
    Plan: TMethodPlan;
    Conversion: TMethodConversion;
    StaticWanted: Boolean;
    Style: TFormatStyle;
    LineBreak: string;
    Works: TObjectList<TFileWork>;
    Warnings: TArray<string>;
    PreviewLines: TArray<string>;
    Calls: Integer;
    /// <summary>Andere Units rufen auf: Deklaration im interface.</summary>
    CalledOutside: Boolean;
    /// <summary>Verwendungen in der Unit der Methode außerhalb ihres Rumpfs (Offsets).</summary>
    FirstUse: Integer;
    HelperName: string;
    HelperNode: TSyntaxNode;
    constructor Create(APlan: TMethodPlan);
    destructor Destroy; override;
    procedure Warn(const AText: string);
    /// <summary>Warnung: Der Ausdruck vor dem Namen wird nicht mehr ausgewertet.</summary>
    procedure WarnLost(AWork: TFileWork; ALine: Integer; AReceiver: TSyntaxNode);
    function AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
    procedure NoteUse(AWork: TFileWork; AOffset: Integer; ACallee: TSyntaxNode);
    function SiteEdit(AWork: TFileWork; AOffset, ALine: Integer; ACallee, ACall: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    function RoutineCallEdit(AWork: TFileWork; AOffset, ALine: Integer; AReceiver: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    function HelperCallEdit(AWork: TFileWork; ALine: Integer; AReceiver, ACall: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    procedure RecordEdit(AWork: TFileWork; ALine: Integer; const AEdit: TOffsetEdit);
    function DeclaringEdits(out AReason: string): Boolean;
    procedure ClassMethodEdits;
    function RoutineEdits(out AReason: string): Boolean;
    function HelperEdits(out AReason: string): Boolean;
    function InsertIntoHelper(const ADecl, AInner: string): string;
    procedure AddHelperAfterClass(const ADecl, AInner: string);
    procedure AddHelperInImplementation(const ADecl, AInner: string);
    function QualifyStatics: TArray<TOffsetEdit>;
    function ChooseHelper(out AReason: string): Boolean;
    function ExistingHelperIssue(AFound: TSyntaxNode): string;
    function NewHelperIssue(const AVisible: string): string;
    function WorkIssue(AWork: TFileWork; out AItem: TMethodFileEdits): string;
    function Finish(out AResult: TMethodResult; out AReason: string): Boolean;
  end;

constructor TMethodBuild.Create(APlan: TMethodPlan);
begin
  inherited Create;
  Plan := APlan;
  Works := TObjectList<TFileWork>.Create(True);
  LineBreak := TTextLines.LineBreakOf(APlan.Text);
  FirstUse := MaxInt;
end;

destructor TMethodBuild.Destroy;
begin
  Works.Free;
  inherited;
end;

procedure TMethodBuild.Warn(const AText: string);
begin
  if IndexStr(AText, Warnings) < 0 then
  begin
    Warnings := Warnings + [AText];
  end;
end;

procedure TMethodBuild.WarnLost(AWork: TFileWork; ALine: Integer; AReceiver: TSyntaxNode);
begin
  Warn(cTexts[TEditingMethodWithoutSelfText.IsNoLongerEvaluated].Fmt([Where(AWork.FileName, ALine),
    TRoutineBody.TextOf(AWork.Text, AReceiver)]));
end;

/// <summary>Verwendungen, die sich nicht umstellen lassen; '' sonst.</summary>
function UseIssue(AUse: TMethodUse; AIsPointer: Boolean): string;
begin
  Result := '';
  if AIsPointer then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsedAsAMethodPointer].Text);
  end;
  case AUse of
    TMethodUse.Inherited_:
      Result := cTexts[TEditingMethodWithoutSelfText.InheritedCall].Text;
    TMethodUse.Accessor:
      Result := cTexts[TEditingMethodWithoutSelfText.AccessorOfAProperty].Text;
    TMethodUse.Unknown:
      Result := cTexts[TEditingMethodWithoutSelfText.UseNotRecognized].Text;
    TMethodUse.Call, TMethodUse.Value, TMethodUse.Pointer: ;
  end;
end;

function IsSelfNode(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self');
end;

/// <summary>Aufruf über eine Variablenkette auf die Klasse umstellen (K.X → TKunde.X).</summary>
function ClassCallEdit(AReceiver: TSyntaxNode; const AClassName: string; out AEdit: TOffsetEdit): Boolean;
begin
  Result := (AReceiver <> nil) and TRoutineBody.IsVariableChain(AReceiver) and not IsSelfNode(AReceiver);
  if Result then
  begin
    AEdit := TOffsetEdit.Create(AReceiver.StartOffset, AReceiver.EndOffset, AClassName);
  end;
end;

/// <summary>Aufruf des Helpers: S.X(Rest) bzw. (Ausdruck).X(Rest).</summary>
function HelperCallText(const AText: string; ACall: TSyntaxNode; const AName: string): string;
var
  mFirst: TSyntaxNode;
begin
  mFirst := ACall[1];
  Result := TRoutineBody.TextOf(AText, mFirst);
  if not TRoutineBody.IsVariableChain(mFirst) then
  begin
    Result := '(' + Result + ')';
  end;
  Result := Result + '.' + AName;
  if ACall.ChildCount > 2 then
  begin
    Result := Result + '(' + Copy(AText, ACall[2].StartOffset + 1, ACall[ACall.ChildCount - 1].EndOffset -
      ACall[2].StartOffset) + ')';
  end;
end;

function TMethodBuild.AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
var
  mCallee, mCall: TSyntaxNode;
  mUse: TMethodUse;
  mLine: Integer;
  mEdit: TOffsetEdit;
begin
  mLine := AWork.Lines.PositionAt(AOffset).Line;
  mUse := TMethodWithoutSelf.UseAt(AWork.Tree, AOffset, Plan.Target.Name, mCallee, mCall);
  AReason := UseIssue(mUse, Plan.IsPointer(mUse));
  if (AReason = '') and (Conversion = TMethodConversion.Helper) and ((mCall = nil) or (mCall.ChildCount < 2)) then
  begin
    AReason := cTexts[TEditingMethodWithoutSelfText.CallWithoutArguments].Text;
  end;
  if AReason <> '' then
  begin
    AReason := Where(AWork.FileName, mLine) + ': ' + AReason;
    Exit(False);
  end;
  NoteUse(AWork, AOffset, mCallee);
  if SiteEdit(AWork, AOffset, mLine, mCallee, mCall, mEdit) then
  begin
    RecordEdit(AWork, mLine, mEdit);
  end
  else if (Conversion in [TMethodConversion.Routine, TMethodConversion.Helper]) and not AWork.Declaring then
  begin
    AWork.NeedsUses := True;
  end;
  Result := True;
end;

procedure TMethodBuild.NoteUse(AWork: TFileWork; AOffset: Integer; ACallee: TSyntaxNode);
begin
  if AWork.Declaring and not TRoutineBody.Within(ACallee, Plan.Routine) and (AOffset < FirstUse) then
  begin
    FirstUse := AOffset;
  end;
  if not AWork.Declaring then
  begin
    CalledOutside := True;
  end;
end;

function TMethodBuild.SiteEdit(AWork: TFileWork; AOffset, ALine: Integer; ACallee, ACall: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
var
  mReceiver: TSyntaxNode;
begin
  AEdit := TOffsetEdit.Create(0, 0, '');
  mReceiver := nil;
  if ACallee.Kind = TSyntaxKind.MemberAccess then
  begin
    mReceiver := ACallee[0];
  end;
  case Conversion of
    TMethodConversion.ClassMethodCalls:
      Result := ClassCallEdit(mReceiver, Plan.Target.ClassName, AEdit);
    TMethodConversion.Routine:
      Result := RoutineCallEdit(AWork, AOffset, ALine, mReceiver, AEdit);
    TMethodConversion.Helper:
      Result := HelperCallEdit(AWork, ALine, mReceiver, ACall, AEdit);
  else
    Result := False;
  end;
end;

/// <summary>Aufruf ohne Objektbezug; qualifiziert, wenn die aufrufende Unit den Namen selbst deklariert.</summary>
function TMethodBuild.RoutineCallEdit(AWork: TFileWork; AOffset, ALine: Integer; AReceiver: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
var
  mPrefix: string;
begin
  mPrefix := '';
  if not AWork.Declaring and (IndexText(Plan.Target.Name, AWork.Names) >= 0) then
  begin
    mPrefix := Plan.UnitName + '.';
  end;
  if AReceiver <> nil then
  begin
    if not TRoutineBody.IsVariableChain(AReceiver) then
    begin
      WarnLost(AWork, ALine, AReceiver);
    end;
    AEdit := TOffsetEdit.Create(AReceiver.StartOffset, AOffset, mPrefix);
    Exit(True);
  end;
  Result := mPrefix <> '';
  if Result then
  begin
    AEdit := TOffsetEdit.Create(AOffset, AOffset, mPrefix);
  end;
end;

function TMethodBuild.HelperCallEdit(AWork: TFileWork; ALine: Integer; AReceiver, ACall: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
begin
  if (AReceiver <> nil) and not TRoutineBody.IsVariableChain(AReceiver) then
  begin
    WarnLost(AWork, ALine, AReceiver);
  end;
  AEdit := TOffsetEdit.Create(ACall.StartOffset, ACall.EndOffset, HelperCallText(AWork.Text, ACall,
    Plan.Target.Name));
  Result := True;
end;

/// <summary>Bearbeitung übernehmen, Aufruf zählen und, wenn sie in einer Zeile bleibt, in die Vorschau.</summary>
procedure TMethodBuild.RecordEdit(AWork: TFileWork; ALine: Integer; const AEdit: TOffsetEdit);
var
  mBefore, mAfter: string;
begin
  AWork.Edits := AWork.Edits + [AEdit];
  if not AWork.Declaring then
  begin
    AWork.NeedsUses := True;
  end;
  Inc(Calls);
  if AWork.Lines.PositionAt(AEdit.Start).Line = AWork.Lines.PositionAt(AEdit.Stop).Line then
  begin
    mBefore := LineText(AWork.Text, AWork.Lines, ALine);
    mAfter := TRoutineParts.ApplyEdits(mBefore, AWork.Lines.LineStart(ALine), [AEdit]);
    PreviewLines := PreviewLines + [Format('%s: %s → %s', [Where(AWork.FileName, ALine), Trim(mBefore),
      Trim(mAfter)])];
  end;
end;

function TMethodBuild.QualifyStatics: TArray<TOffsetEdit>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in Plan.Statics do
  begin
    Result := Result + [TOffsetEdit.Create(mNode.StartOffset, mNode.StartOffset, Plan.Target.ClassName + '.')];
  end;
end;

procedure TMethodBuild.ClassMethodEdits;
var
  mWork: TFileWork;
  mWithStatic: Boolean;
begin
  mWork := Works[0];
  mWithStatic := StaticWanted or Plan.Target.IsRecord;
  if mWithStatic and Plan.UsesClassLevel and not Plan.Target.IsRecord then
  begin
    mWithStatic := False;
    Warn(cTexts[TEditingMethodWithoutSelfText.StaysWithoutStaticTheBody].Fmt([Plan.Target.Name]));
  end;
  mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Declaration.StartOffset, Plan.Declaration.StartOffset,
    'class '), TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.StartOffset, 'class ')];
  if mWithStatic then
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Declaration.EndOffset, Plan.Declaration.EndOffset,
      ' static;')];
  end;
end;

/// <summary>Bearbeitungen, die AInner (im Bereich AStart..AStop) in den verschobenen Text übernehmen; die übrigen
/// bleiben in AEdits.</summary>
function SplitEdits(var AEdits: TArray<TOffsetEdit>; AStart, AStop: Integer): TArray<TOffsetEdit>;
var
  mKept: TArray<TOffsetEdit>;
  mEdit: TOffsetEdit;
begin
  Result := nil;
  mKept := nil;
  for mEdit in AEdits do
  begin
    if (mEdit.Start >= AStart) and (mEdit.Stop <= AStop) then
    begin
      Result := Result + [mEdit];
    end
    else
    begin
      mKept := mKept + [mEdit];
    end;
  end;
  AEdits := mKept;
end;

/// <summary>Oberste Routine der Implementierung, die AOffset enthält; nil ohne.</summary>
function TopLevelAt(AImplementation: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AImplementation.ChildCount - 1 do
  begin
    if (AImplementation[mIndex].Kind = TSyntaxKind.RoutineDecl) and
      TRoutineParts.Encloses(AImplementation[mIndex], AOffset) then
    begin
      Exit(AImplementation[mIndex]);
    end;
  end;
end;

/// <summary>Bereich der Routine samt Kommentaren darüber bis zum Anfang der Folgezeile, dazu eine Leerzeile
/// dahinter.</summary>
procedure RoutineSpan(const AText: string; const ALines: TLineTable; ARoutine: TSyntaxNode; out AStart,
  AStop: Integer);
var
  mNext: Integer;
begin
  AStart := ALines.LineStart(TRoutineBody.RoutineInsertLine(AText, ARoutine));
  mNext := ARoutine.EndPos.Line + 1;
  AStop := ALines.LineStart(mNext);
  if mNext >= ALines.LineCount then
  begin
    AStop := Length(AText);
  end
  else if Trim(LineText(AText, ALines, mNext)) = '' then
  begin
    AStop := ALines.LineStart(mNext + 1);
  end;
end;

function TMethodBuild.RoutineEdits(out AReason: string): Boolean;
var
  mWork: TFileWork;
  mHead, mMoved: string;
  mImplementation_, mFirst: TSyntaxNode;
  mStart, mStop, mInsertAt, mLine: Integer;
  mInner: TArray<TOffsetEdit>;
begin
  mWork := Works[0];
  if CalledOutside and not Plan.ClassInInterface then
  begin
    Exit(Fail(cTexts[TEditingMethodWithoutSelfText.OtherUnitsCallItBut].Text, AReason));
  end;
  mHead := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, Plan.Parameters, False);
  mWork.Edits := mWork.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  if CalledOutside then
  begin
    // Vor implementation, mit Leerzeile.
    mLine := Plan.Routine.Parent.StartPos.Line;
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(mLine), Plan.Lines.LineStart(mLine),
      mHead + KeptDirectives(Plan.Text, Plan.Declaration) + LineBreak + LineBreak)];
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset, mHead)];
  end
  else
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
      mHead + KeptDirectives(Plan.Text, Plan.Declaration))];
  end;
  mWork.Edits := mWork.Edits + QualifyStatics;
  // Ohne Deklaration im interface muss die Routine vor ihrer ersten Verwendung stehen.
  if not CalledOutside and (FirstUse < Plan.Routine.StartOffset) then
  begin
    mImplementation_ := Plan.Routine.Parent;
    mFirst := TopLevelAt(mImplementation_, FirstUse);
    if mFirst = nil then
    begin
      Exit(Fail(cTexts[TEditingMethodWithoutSelfText.FirstUseNotInA].Text, AReason));
    end;
    RoutineSpan(Plan.Text, Plan.Lines, Plan.Routine, mStart, mStop);
    mInner := SplitEdits(mWork.Edits, mStart, mStop);
    mMoved := TRoutineParts.ApplyEdits(Copy(Plan.Text, mStart + 1, mStop - mStart), mStart, mInner);
    if not EndsStr(LineBreak + LineBreak, mMoved) then
    begin
      mMoved := mMoved + LineBreak;
    end;
    mInsertAt := Plan.Lines.LineStart(TRoutineBody.RoutineInsertLine(Plan.Text, mFirst));
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(mStart, mStop, ''), TOffsetEdit.Create(mInsertAt, mInsertAt,
      mMoved)];
  end;
  Result := True;
end;

/// <summary>record helper der Unit für ATypeName; nil ohne.</summary>
function ExistingHelper(ATree: TSyntaxTree; const ATypeName: string): TSyntaxNode;
var
  mTypeName: string;
begin
  mTypeName := ATypeName;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.HelperType) and SameText(ANode.Name, 'record') and (ANode.ChildCount > 0) and
        (ANode[0].Kind = TSyntaxKind.TypeReference) and
        SameTypeName(TMethodLookup.HeadName(ANode[0].Name), mTypeName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

function TMethodBuild.ExistingHelperIssue(AFound: TSyntaxNode): string;
var
  mInterface: TSyntaxNode;
begin
  Result := '';
  mInterface := Plan.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if CalledOutside and ((mInterface = nil) or not TRoutineBody.Within(AFound, mInterface)) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.TheHelperIsInThe].Fmt([AFound.Parent.Name]));
  end;
  HelperNode := AFound;
  HelperName := AFound.Parent.Name;
end;

function TMethodBuild.NewHelperIssue(const AVisible: string): string;
var
  mBase: string;
begin
  Result := '';
  if CalledOutside and not Plan.ClassInInterface then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.OtherUnitsCallItBut].Text);
  end;
  mBase := TMethodWithoutSelf.HelperNameFor(Plan.Target.HelperType);
  // Den Namen eines sichtbaren Helpers (TStringHelper der RTL) nicht verdecken: THauptStringHelper.
  if SameText(mBase, AVisible) or (Assigned(Plan.Lookup.NameVisible) and Plan.Lookup.NameVisible(mBase,
    Plan.Routine.StartOffset)) then
  begin
    mBase := 'T' + Capitalized(Plan.UnitName.Substring(Plan.UnitName.LastIndexOf('.') + 1)) + Copy(mBase, 2,
      MaxInt);
  end;
  HelperName := TRoutineParts.FreeName(mBase, TRoutineParts.UnitNames(Plan.Tree.Root));
end;

function TMethodBuild.ChooseHelper(out AReason: string): Boolean;
var
  mFound: TSyntaxNode;
  mTypeName, mVisible: string;
begin
  mTypeName := Plan.Target.HelperType;
  mFound := ExistingHelper(Plan.Tree, mTypeName);
  mVisible := '';
  if Assigned(Plan.Lookup.VisibleHelper) then
  begin
    mVisible := Plan.Lookup.VisibleHelper(mTypeName, Plan.Routine.StartOffset);
  end;
  if mFound <> nil then
  begin
    AReason := ExistingHelperIssue(mFound);
  end
  else
  begin
    AReason := NewHelperIssue(mVisible);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  if (mVisible <> '') and not SameText(mVisible, HelperName) then
  begin
    Warn(cTexts[TEditingMethodWithoutSelfText.IsAlreadyVisibleFor].Fmt([mTypeName, mVisible, HelperName, mVisible]));
  end;
  Result := True;
end;

/// <summary>Letztes end im Bereich von ANode; -1 ohne.</summary>
function LastEndToken(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if ATokens[mIndex].IsKeyword('end') then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Deklaration vor das end des vorhandenen Helpers.</summary>
function TMethodBuild.InsertIntoHelper(const ADecl, AInner: string): string;
var
  mEndToken, mLine: Integer;
begin
  Result := '';
  mEndToken := LastEndToken(Plan.Tokens, HelperNode);
  if mEndToken < 0 then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.EndOfTheHelperNot].Text);
  end;
  mLine := Plan.Tokens[mEndToken].StartPos.Line;
  if Trim(Copy(LineText(Plan.Text, Plan.Lines, mLine), 1, Plan.Tokens[mEndToken].StartPos.Character)) <> '' then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.EndOfTheHelperIs].Text);
  end;
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(mLine),
    Plan.Lines.LineStart(mLine), IndentAt(Plan.Text, Plan.Lines, mLine) + AInner + ADecl + LineBreak)];
end;

/// <summary>Neuer Helper hinter der Klasse, im selben type-Abschnitt.</summary>
procedure TMethodBuild.AddHelperAfterClass(const ADecl, AInner: string);
var
  mTypeDecl: TSyntaxNode;
  mIndent, mBlock: string;
  mAt: Integer;
begin
  mTypeDecl := Plan.TypeBody.Parent;
  mIndent := IndentAt(Plan.Text, Plan.Lines, mTypeDecl.StartPos.Line);
  mBlock := LineBreak + mIndent + HelperName + ' = record helper for ' + Plan.Target.HelperType + LineBreak +
    mIndent + AInner + ADecl + LineBreak + mIndent + 'end;' + LineBreak;
  mAt := Plan.Lines.LineStart(mTypeDecl.EndPos.Line + 1);
  if mTypeDecl.EndPos.Line + 1 >= Plan.Lines.LineCount then
  begin
    mAt := Length(Plan.Text);
  end;
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(mAt, mAt, mBlock)];
end;

/// <summary>Neuer Helper am Anfang von implementation, hinter dessen uses.</summary>
procedure TMethodBuild.AddHelperInImplementation(const ADecl, AInner: string);
var
  mImplementation, mClause: TSyntaxNode;
  mLine, mAt: Integer;
  mBlock: string;
begin
  mImplementation := Plan.Routine.Parent;
  mClause := mImplementation.FindChild(TSyntaxKind.UsesClause);
  mLine := mImplementation.StartPos.Line + 1;
  if mClause <> nil then
  begin
    mLine := mClause.EndPos.Line + 1;
  end;
  mBlock := LineBreak + 'type' + LineBreak + AInner + HelperName + ' = record helper for ' +
    Plan.Target.HelperType + LineBreak + AInner + AInner + ADecl + LineBreak + AInner + 'end;' + LineBreak;
  mAt := Plan.Lines.LineStart(mLine);
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(mAt, mAt, mBlock)];
end;

function TMethodBuild.HelperEdits(out AReason: string): Boolean;
var
  mWork: TFileWork;
  mRest: TArray<TParameterText>;
  mDecl, mInner: string;
  mNode: TSyntaxNode;
begin
  if not ChooseHelper(AReason) then
  begin
    Exit(False);
  end;
  mWork := Works[0];
  mRest := Copy(Plan.Parameters, 1, MaxInt);
  mDecl := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, mRest, False) +
    KeptDirectives(Plan.Text, Plan.Declaration);
  mInner := TRoutineBody.IndentUnit(Style);
  mWork.Edits := mWork.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  AReason := '';
  if HelperNode <> nil then
  begin
    AReason := InsertIntoHelper(mDecl, mInner);
  end
  else if CalledOutside then
  begin
    AddHelperAfterClass(mDecl, mInner);
  end
  else
  begin
    AddHelperInImplementation(mDecl, mInner);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
    TRoutineParts.HeadText(Plan.Text, Plan.Declaration, HelperName + '.' + Plan.Target.Name, mRest, False))];
  mWork.Edits := mWork.Edits + QualifyStatics;
  for mNode in Plan.FirstParameterNodes do
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(mNode.StartOffset, mNode.EndOffset, 'Self')];
  end;
  Result := True;
end;

function TMethodBuild.DeclaringEdits(out AReason: string): Boolean;
begin
  case Conversion of
    TMethodConversion.Routine:
      Result := RoutineEdits(AReason);
    TMethodConversion.Helper:
      Result := HelperEdits(AReason);
  else
    // class-Methode gelingt immer.
    ClassMethodEdits;
    Result := True;
  end;
end;

/// <summary>Überschneiden sich zwei Bearbeitungen (gleiche Einfügestelle zählt nicht)?</summary>
function Overlapping(const AEdits: TArray<TOffsetEdit>): Boolean;
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to High(AEdits) do
  begin
    for mOther := mIndex + 1 to High(AEdits) do
    begin
      if (AEdits[mIndex].Start < AEdits[mOther].Stop) and (AEdits[mOther].Start < AEdits[mIndex].Stop) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Bearbeitungen einer Datei als Textänderungen, samt uses für die Unit AUnitName.</summary>
function TextEditsOf(AWork: TFileWork; const AUnitName: string): TMethodFileEdits;
var
  mEdit: TOffsetEdit;
  mUsesEdits: TArray<TTextEdit>;
  mAdded: TArray<string>;
begin
  Result.FileName := AWork.FileName;
  Result.Edits := nil;
  for mEdit in AWork.Edits do
  begin
    Result.Edits := Result.Edits + [TTextEdit.Create(TTextRange.Create(AWork.Lines.PositionAt(mEdit.Start),
      AWork.Lines.PositionAt(mEdit.Stop)), mEdit.Text)];
  end;
  if AWork.NeedsUses and TUsesActions.AddUnits(AWork.Tree.Tokens, TUsesAddRequest.Create(
    TArray<string>.Create(AUnitName), nil, nil, TTextLines.LineBreakOf(AWork.Text)), mUsesEdits, mAdded) then
  begin
    Result.Edits := Result.Edits + mUsesEdits;
  end;
end;

/// <summary>Parst die Datei nach den Änderungen nicht mehr fehlerfrei?</summary>
function ParseIssue(AWork: TFileWork; const AEdits: TArray<TTextEdit>): string;
var
  mTree: TSyntaxTree;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(TChangeSignature.ApplyEdits(AWork.Text, AEdits));
  try
    if Length(mTree.Diagnostics) > Length(AWork.Tree.Diagnostics) then
    begin
      Result := cTexts[TEditingMethodWithoutSelfText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AWork.FileName),
        mTree.Diagnostics[0].StartPos.Line + 1, mTree.Diagnostics[0].Message]);
    end;
  finally
    mTree.Free;
  end;
end;

function TMethodBuild.WorkIssue(AWork: TFileWork; out AItem: TMethodFileEdits): string;
begin
  AItem := Default(TMethodFileEdits);
  if Overlapping(AWork.Edits) then
  begin
    Exit(Where(AWork.FileName, 0) + cTexts[TEditingMethodWithoutSelfText.NestedCalls].Text);
  end;
  AItem := TextEditsOf(AWork, Plan.UnitName);
  Result := '';
  if AItem.Edits <> nil then
  begin
    Result := ParseIssue(AWork, AItem.Edits);
  end;
end;

/// <summary>Was geschieht, für die Vorschau.</summary>
function ActionText(AConversion: TMethodConversion; const ATarget: TMethodTarget; const AHelperName: string): string;
begin
  case AConversion of
    TMethodConversion.Routine:
      Result := cTexts[TEditingMethodWithoutSelfText.BecomesAFreeRoutine].Fmt([ATarget.ClassName, ATarget.Name]);
    TMethodConversion.Helper:
      Result := cTexts[TEditingMethodWithoutSelfText.MovesToRecordHelperFor].Fmt([ATarget.ClassName, ATarget.Name,
        AHelperName, ATarget.HelperType]);
  else
    Result := cTexts[TEditingMethodWithoutSelfText.BecomesAClassMethod].Fmt([ATarget.ClassName, ATarget.Name]);
  end;
end;

function TMethodBuild.Finish(out AResult: TMethodResult; out AReason: string): Boolean;
var
  mWork: TFileWork;
  mItem: TMethodFileEdits;
begin
  AResult := Default(TMethodResult);
  AReason := '';
  for mWork in Works do
  begin
    AReason := WorkIssue(mWork, mItem);
    if AReason <> '' then
    begin
      Exit(False);
    end;
    if mItem.Edits <> nil then
    begin
      AResult.Files := AResult.Files + [mItem];
    end;
  end;
  AResult.Preview := ActionText(Conversion, Plan.Target, HelperName) +
    cTexts[TEditingMethodWithoutSelfText.ChangedCalls].Fmt([Calls]);
  if PreviewLines <> nil then
  begin
    AResult.Preview := AResult.Preview + sLineBreak + string.Join(sLineBreak, PreviewLines);
  end;
  AResult.Warnings := Warnings;
  AResult.Calls := Calls;
  Result := True;
end;

{ TMethodWithoutSelf }

class function TMethodWithoutSelf.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TMethodLookup; out ATarget: TMethodTarget; out AReason: string): Boolean;
var
  mPlan: TMethodPlan;
begin
  ATarget := Default(TMethodTarget);
  AReason := '';
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(Fail(cTexts[TEditingMethodWithoutSelfText.NoTree].Text, AReason));
  end;
  mPlan := TMethodPlan.Create(AText, ATree, ALookup);
  try
    Result := mPlan.Analyze(mPlan.Lines.OffsetAt(APosition), AReason);
    if Result then
    begin
      ATarget := mPlan.Target;
    end;
  finally
    mPlan.Free;
  end;
end;

class function TMethodWithoutSelf.Candidates(const AText: string; ATree: TSyntaxTree;
  const ALookup: TMethodLookup): TArray<TMethodTarget>;
var
  mImplementation_, mRoutine, mHeader: TSyntaxNode;
  mIndex: Integer;
  mFound: TMethodTarget;
  mReason: string;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mImplementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mImplementation_ = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mImplementation_.ChildCount - 1 do
  begin
    mRoutine := mImplementation_[mIndex];
    if (mRoutine.Kind <> TSyntaxKind.RoutineDecl) or (TRoutineBody.QualifierOf(mRoutine.Name) = '') then
    begin
      Continue;
    end;
    mHeader := TRoutineParts.HeaderOf(mRoutine);
    if (mHeader <> nil) and Target(AText, ATree, mHeader.EndPos, ALookup, mFound, mReason) then
    begin
      Result := Result + [mFound];
    end;
  end;
end;

/// <summary>Verwendung des gefundenen Namens nach seinem Elternknoten; ACall: der Aufruf mit Argumenten.</summary>
function FoundUse(AFound: TSyntaxNode; out ACall: TSyntaxNode): TMethodUse;
var
  mParent: TSyntaxNode;
begin
  ACall := nil;
  mParent := AFound.Parent;
  if mParent = nil then
  begin
    Result := TMethodUse.Value;
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent[0] = AFound) then
  begin
    ACall := mParent;
    Result := TMethodUse.Call;
  end
  else if mParent.Kind = TSyntaxKind.CallStatement then
  begin
    Result := TMethodUse.Call;
  end
  else if mParent.Kind = TSyntaxKind.AddressOf then
  begin
    Result := TMethodUse.Pointer;
  end
  else
  begin
    Result := TMethodUse.Value;
  end;
end;

class function TMethodWithoutSelf.UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string;
  out ACallee, ACall: TSyntaxNode): TMethodUse;
var
  mScan: TMethodUseScan;
begin
  ACallee := nil;
  ACall := nil;
  mScan := TMethodUseScan.Scan(ATree, AOffset, AName);
  if mScan.InProperty then
  begin
    Result := TMethodUse.Accessor;
  end
  else if mScan.InInherited then
  begin
    Result := TMethodUse.Inherited_;
  end
  else if mScan.Found = nil then
  begin
    Result := TMethodUse.Unknown;
  end
  else
  begin
    ACallee := mScan.Found;
    Result := FoundUse(mScan.Found, ACall);
  end;
end;

/// <summary>Analyse der Methode und Grund, warum die gewählte Umwandlung nicht geht; '' = geht.</summary>
function ConversionIssue(APlan: TMethodPlan; const ARequest: TMethodRequest): string;
begin
  if not APlan.Analyze(APlan.Lines.OffsetAt(ARequest.Position), Result) then
  begin
    Exit;
  end;
  case ARequest.Conversion of
    TMethodConversion.Routine:
      Result := APlan.Target.RoutineReason;
    TMethodConversion.Helper:
      Result := APlan.Target.HelperReason;
  else
    Result := '';
  end;
end;

procedure AddWorks(ABuild: TMethodBuild; const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>);
var
  mSource: TMethodSource;
begin
  ABuild.Works.Add(TFileWork.Create(ADeclaring, True));
  for mSource in AOthers do
  begin
    if (mSource.Tree <> nil) and not SameText(mSource.FileName, ADeclaring.FileName) then
    begin
      ABuild.Works.Add(TFileWork.Create(mSource, False));
    end;
  end;
end;

/// <summary>Deklaration und Kopf der Implementierung zählen nicht als Verwendung.</summary>
function IsOwnHead(APlan: TMethodPlan; AWork: TFileWork; AOffset: Integer): Boolean;
begin
  Result := AWork.Declaring and (TRoutineParts.Encloses(APlan.Declaration, AOffset) or
    TRoutineParts.Encloses(APlan.Header, AOffset));
end;

function SitesIssue(ABuild: TMethodBuild): string;
var
  mWork: TFileWork;
  mOffset: Integer;
begin
  Result := '';
  for mWork in ABuild.Works do
  begin
    for mOffset in mWork.Offsets do
    begin
      if not IsOwnHead(ABuild.Plan, mWork, mOffset) and not ABuild.AddSite(mWork, mOffset, Result) then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TMethodWithoutSelf.Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
  const ARequest: TMethodRequest; out AResult: TMethodResult; out AReason: string): Boolean;
var
  mPlan: TMethodPlan;
  mBuild: TMethodBuild;
begin
  AResult := Default(TMethodResult);
  AReason := '';
  if (ADeclaring.Tree = nil) or (ADeclaring.Tree.Root = nil) then
  begin
    AReason := cTexts[TEditingMethodWithoutSelfText.NoTree].Text;
    Exit(False);
  end;
  mPlan := TMethodPlan.Create(ADeclaring.Text, ADeclaring.Tree, ARequest.Lookup);
  mBuild := TMethodBuild.Create(mPlan);
  try
    AReason := ConversionIssue(mPlan, ARequest);
    if AReason = '' then
    begin
      mBuild.Conversion := ARequest.Conversion;
      mBuild.StaticWanted := ARequest.WithStatic;
      mBuild.Style := ARequest.Style;
      AddWorks(mBuild, ADeclaring, AOthers);
      AReason := SitesIssue(mBuild);
    end;
    Result := (AReason = '') and mBuild.DeclaringEdits(AReason) and mBuild.Finish(AResult, AReason);
  finally
    mBuild.Free;
    mPlan.Free;
  end;
end;

class function TMethodWithoutSelf.ConversionName(AConversion: TMethodConversion): string;
begin
  case AConversion of
    TMethodConversion.ClassMethodCalls:
      Result := 'classMethodCalls';
    TMethodConversion.Routine:
      Result := 'routine';
    TMethodConversion.Helper:
      Result := 'helper';
  else
    Result := 'classMethod';
  end;
end;

class function TMethodWithoutSelf.ConversionOf(const AName: string; out AConversion: TMethodConversion): Boolean;
var
  mItem: TMethodConversion;
begin
  for mItem := Low(TMethodConversion) to High(TMethodConversion) do
  begin
    if SameText(ConversionName(mItem), AName) then
    begin
      AConversion := mItem;
      Exit(True);
    end;
  end;
  AConversion := TMethodConversion.ClassMethod;
  Result := False;
end;

class function TMethodWithoutSelf.IsSimpleType(const ATypeName: string): Boolean;
begin
  Result := IndexText(Trim(ATypeName), cSimpleTypes) >= 0;
end;

class function TMethodWithoutSelf.HelperNameFor(const ATypeName: string): string;
var
  mName: string;
begin
  mName := Trim(ATypeName);
  if (Length(mName) > 1) and (mName[1] = 'T') and CharInSet(mName[2], ['A'..'Z']) then
  begin
    mName := Copy(mName, 2, MaxInt);
  end;
  if SameText(mName, 'UnicodeString') then
  begin
    mName := 'String';
  end;
  Result := 'T' + Capitalized(mName) + 'Helper';
end;

end.
