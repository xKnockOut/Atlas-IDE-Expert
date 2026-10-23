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
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Namens im Rumpf einer Methode.</summary>
  TMemberLevel = (NotMember, Instance, ClassLevel, StaticLevel, Unknown);
  /// <summary>Umwandlung: class-Methode, class-Methode samt Aufrufen über die Klasse, freie Routine, Helper.</summary>
  TMethodConversion = (ClassMethod, ClassMethodCalls, Routine, Helper);
  /// <summary>Verwendung der Methode an einer Stelle.</summary>
  TMethodUse = (Call, Value, Pointer, Inherited_, Accessor, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Art des Bezeichners bzw. Typnamens ANode im Rumpf; AVisibility bei Mitgliedern.</summary>
  TMemberLevelFunc = reference to function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel;
  /// <summary>Hat das Interface ATypeName ein Mitglied AName (sichtbar an AOffset)?</summary>
  TMethodTypeMemberFunc = reference to function(const ATypeName, AName: string; AOffset: Integer): Boolean;
  /// <summary>Name des an AOffset sichtbaren Helpers für ATypeName, '' ohne.</summary>
  TMethodHelperFunc = reference to function(const ATypeName: string; AOffset: Integer): string;
  /// <summary>Steht AName in der Formulardatei?</summary>
  TMethodInFormFunc = reference to function(const AName: string): Boolean;
  /// <summary>Ist der Name AName an AOffset schon sichtbar (Typ einer anderen Unit)?</summary>
  TMethodNameVisibleFunc = reference to function(const AName: string; AOffset: Integer): Boolean;

  TMethodLookup = record
    MemberLevel: TMemberLevelFunc;
    InterfaceMember: TMethodTypeMemberFunc;
    InForm: TMethodInFormFunc;
    VisibleHelper: TMethodHelperFunc;
    NameVisible: TMethodNameVisibleFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (var-Argumente schreiben).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Mitglieder der Klasse in der Datei; bei einem Vorfahren außer TObject
    /// sind andere Namen unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TMethodLookup; static;
    /// <summary>Über AResolver für ATree der Datei AFileName (Baum festhalten, solange gebraucht).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TMethodLookup; static;
  end;

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
    ClassMethodTitle = 'In class-Methode umwandeln';
    ClassMethodCallsTitle = 'In class-Methode umwandeln, Aufrufe über %s';
    RoutineTitle = 'In freie Routine umwandeln';
    HelperTitle = 'In Record-Helper für %s verschieben';
    MarkerText = 'ohne Self';
  public
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
    /// <summary>Wandelt die Methode an APosition in ADeclaring um; AOthers: weitere Dateien mit Verwendungen.
    /// AStatic: refactoring.methodKindStatic.</summary>
    class function Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
      const APosition: TTextPosition; AConversion: TMethodConversion; AStatic: Boolean;
      const ALookup: TMethodLookup; const AStyle: TFormatStyle; out AResult: TMethodResult;
      out AReason: string): Boolean; static;
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
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Editing.UsesActions;

const
  SimpleTypes: array[0..27] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char',
    'WideChar', 'AnsiChar', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Currency', 'Boolean',
    'TDateTime', 'TDate', 'TTime', 'TGUID');
  // Helper der RTL (System.SysUtils, System.Character), falls der Index sie nicht kennt.
  RtlHelpedTypes: array[0..14] of string = ('string', 'UnicodeString', 'Integer', 'Cardinal', 'Int64', 'UInt64',
    'NativeInt', 'NativeUInt', 'Byte', 'Word', 'ShortInt', 'SmallInt', 'Double', 'Single', 'Boolean');
  RtlHelpers: array[0..14] of string = ('TStringHelper', 'TStringHelper', 'TIntegerHelper', 'TCardinalHelper',
    'TInt64Helper', 'TUInt64Helper', 'TNativeIntHelper', 'TNativeUIntHelper', 'TByteHelper', 'TWordHelper',
    'TShortIntHelper', 'TSmallIntHelper', 'TDoubleHelper', 'TSingleHelper', 'TBooleanHelper');
  // Direktiven, die an einer freien Routine bzw. einem Helper nicht passen.
  DroppedDirectives: array[0..8] of string = ('overload', 'reintroduce', 'final', 'static', 'virtual', 'dynamic',
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
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
end;

/// <summary>Erster Teil eines Typ- oder Bezeichnernamens: TInner aus TInner&lt;X&gt;, A aus A.B.</summary>
function HeadName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  if Pos('.', Result) > 0 then
    Result := Copy(Result, 1, Pos('.', Result) - 1);
  Result := Trim(Result);
end;

function SameTypeName(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or (MatchText(A, ['string', 'UnicodeString']) and MatchText(B, ['string',
    'UnicodeString']));
end;

/// <summary>Knoten unter AParent (ohne ihn), der ANode enthält; nil, wenn ANode nicht darunter liegt.</summary>
function ChildOn(AParent, ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Parent <> AParent) do
    Result := Result.Parent;
end;

function Where(const AFileName: string; ALine: Integer): string;
begin
  if AFileName = '' then
    Result := Format('Zeile %d', [ALine + 1])
  else
    Result := Format('%s, Zeile %d', [ExtractFileName(AFileName), ALine + 1]);
end;

{ TMethodLookup }

/// <summary>Klasse bzw. Record, zu dessen Methode ANode gehört; nil außerhalb.</summary>
function OwnerBody(ATree: TSyntaxTree; ANode: TSyntaxNode): TSyntaxNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := ANode;
  while Node <> nil do
  begin
    if (Node.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
      Exit(Node);
    if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.Parent <> nil) and
      (Node.Parent.Kind = TSyntaxKind.ImplementationSection) then
    begin
      if TRoutineBody.QualifierOf(Node.Name) <> '' then
        Result := TRoutineBody.TypeBody(ATree.Root, TRoutineBody.QualifierOf(Node.Name));
      Exit;
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>Beginnt der Knoten (Abschnitt oder Kopf) mit class?</summary>
function StartsWithClass(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  if (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class') then
    Exit(True);
  // class var: Der Abschnitt beginnt erst bei var.
  Index := TRoutineBody.PreviousToken(ATokens, Index);
  Result := (Index >= 0) and ATokens[Index].IsKeyword('class');
end;

function TrimmedNames(const ANames: TArray<string>): TArray<string>;
var
  Index: Integer;
begin
  Result := Copy(ANames, 0, MaxInt);
  for Index := 0 to High(Result) do
    Result[Index] := Trim(Result[Index]);
end;

/// <summary>Art des Mitglieds AName, wie es in ABody deklariert ist; False, wenn ABody es nicht deklariert.</summary>
function DeclaredLevel(const ATokens: TArray<TPascalToken>; ABody: TSyntaxNode; const AName: string;
  out ALevel: TMemberLevel; out AVisibility: TIndexVisibility): Boolean;
var
  Index: Integer;
  Child: TSyntaxNode;
  Visibility: string;
  Names: TArray<string>;
begin
  Result := False;
  Visibility := '';
  AVisibility := TIndexVisibility.Public;
  for Index := 0 to ABody.ChildCount - 1 do
  begin
    Child := ABody[Index];
    if Child.Kind = TSyntaxKind.Visibility then
    begin
      Visibility := LowerCase(Child.Name);
      Continue;
    end;
    Names := nil;
    case Child.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        Names := TRoutineParts.ChildNames(Child);
      TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
        Names := [Child.Name];
      TSyntaxKind.Field:
        Names := Child.Name.Split([',']);
    end;
    if IndexText(AName, TrimmedNames(Names)) < 0 then
      Continue;
    Result := True;
    if Visibility = 'strict private' then
      AVisibility := TIndexVisibility.StrictPrivate
    else if Visibility = 'strict protected' then
      AVisibility := TIndexVisibility.StrictProtected
    else if Visibility = 'private' then
      AVisibility := TIndexVisibility.Private
    else if Visibility = 'protected' then
      AVisibility := TIndexVisibility.Protected;
    case Child.Kind of
      TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        ALevel := TMemberLevel.StaticLevel;
      TSyntaxKind.Field:
        ALevel := TMemberLevel.Instance;
      TSyntaxKind.VarSection:
        if StartsWithClass(ATokens, Child) then
          ALevel := TMemberLevel.StaticLevel
        else
          ALevel := TMemberLevel.Instance;
      TSyntaxKind.RoutineHeader:
        if not StartsWithClass(ATokens, Child) then
          ALevel := TMemberLevel.Instance
        else if TRoutineParts.HasWord(ATokens, Child, ['static']) then
          ALevel := TMemberLevel.StaticLevel
        else
          ALevel := TMemberLevel.ClassLevel;
      TSyntaxKind.PropertyDecl:
        if StartsWithClass(ATokens, Child) then
          ALevel := TMemberLevel.StaticLevel
        else
          ALevel := TMemberLevel.Instance;
    end;
    Exit;
  end;
end;

/// <summary>Hat der Typ ABody einen Vorfahren außer TObject (dessen Mitglieder die Datei nicht kennt)?</summary>
function HasUnknownAncestor(ABody: TSyntaxNode): Boolean;
begin
  Result := (ABody.Kind = TSyntaxKind.ClassType) and (ABody.ChildCount > 0) and
    (ABody[0].Kind = TSyntaxKind.TypeReference) and not MatchText(ABody[0].Name, ['TObject', 'System.TObject']);
end;

class function TMethodLookup.FromTree(ATree: TSyntaxTree): TMethodLookup;
var
  Names: TArray<string>;
begin
  Result := Default(TMethodLookup);
  if ATree = nil then
    Exit;
  Names := TRoutineParts.UnitNames(ATree.Root);
  Result.Flow := TNestedRoutineLookup.FromTree(ATree).Flow;
  Result.MemberLevel :=
    function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel
    var
      Body: TSyntaxNode;
      Name: string;
    begin
      AVisibility := TIndexVisibility.Public;
      Name := HeadName(ANode.Name);
      Body := OwnerBody(ATree, ANode);
      if (Body <> nil) and DeclaredLevel(ATree.Tokens, Body, Name, Result, AVisibility) then
        Exit;
      if ANode.Kind = TSyntaxKind.TypeReference then
        Exit(TMemberLevel.NotMember);
      if (IndexText(Name, Names) >= 0) or TSystemIntrinsics.IsKnown(Name) then
        Exit(TMemberLevel.NotMember);
      if (Body <> nil) and HasUnknownAncestor(Body) then
        Exit(TMemberLevel.Unknown);
      Result := TMemberLevel.NotMember;
    end;
  Result.InterfaceMember :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    var
      Body: TSyntaxNode;
      Index: Integer;
      Name: string;
    begin
      Result := False;
      Name := HeadName(ATypeName);
      Body := ATree.Root.Search(
        function(ANode: TSyntaxNode): TSyntaxSearchStep
        begin
          Result := TSyntaxSearchStep.Descend;
          if (ANode.Kind = TSyntaxKind.InterfaceType) and (ANode.Parent <> nil) and SameText(ANode.Parent.Name, Name)
          then
            Result := TSyntaxSearchStep.Found;
        end);
      if Body = nil then
        Exit;
      for Index := 0 to Body.ChildCount - 1 do
        if (Body[Index].Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl]) and
          SameText(Body[Index].Name, AName) then
          Exit(True);
    end;
  Result.VisibleHelper :=
    function(const ATypeName: string; AOffset: Integer): string
    var
      Index, Section: Integer;
      Clause: TSyntaxNode;
      Used: Boolean;
    begin
      Result := '';
      Index := IndexText(ATypeName, RtlHelpedTypes);
      if Index < 0 then
        Exit;
      Used := False;
      for Section := 0 to ATree.Root.ChildCount - 1 do
      begin
        Clause := ATree.Root[Section].FindChild(TSyntaxKind.UsesClause);
        if (Clause <> nil) and ((IndexText('System.SysUtils', TRoutineParts.ChildNames(Clause)) >= 0) or
          (IndexText('SysUtils', TRoutineParts.ChildNames(Clause)) >= 0)) then
          Used := True;
      end;
      if Used then
        Result := RtlHelpers[Index];
    end;
end;

class function TMethodLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TMethodLookup;
var
  FileName: string;
  Fallback: TMethodLookup;
begin
  Fallback := FromTree(ATree);
  Result := Fallback;
  FileName := AFileName;
  Result.MemberLevel :=
    function(ANode: TSyntaxNode; out AVisibility: TIndexVisibility): TMemberLevel
    var
      Resolved: TResolvedSymbol;
      Name: string;
      IsClass, IsStatic: Boolean;
    begin
      AVisibility := TIndexVisibility.Public;
      Name := HeadName(ANode.Name);
      Resolved := AResolver.Resolve(ATree, FileName, ANode.StartPos);
      if Resolved.Kind = TResolvedKind.None then
      begin
        if TSystemIntrinsics.IsKnown(Name) then
          Exit(TMemberLevel.NotMember);
        Exit(TMemberLevel.Unknown);
      end;
      if (Resolved.Kind <> TResolvedKind.Symbol) or Resolved.Builtin or (Resolved.Container = '') then
        Exit(TMemberLevel.NotMember);
      AVisibility := Resolved.Visibility;
      IsClass := IndexText('class', Resolved.Directives) >= 0;
      IsStatic := IndexText('static', Resolved.Directives) >= 0;
      case Resolved.SymbolKind of
        TIndexSymbolKind.Field, TIndexSymbolKind.Property_:
          if IsClass then
            Result := TMemberLevel.StaticLevel
          else
            Result := TMemberLevel.Instance;
        TIndexSymbolKind.Method:
          if IsClass and IsStatic then
            Result := TMemberLevel.StaticLevel
          else if IsClass then
            Result := TMemberLevel.ClassLevel
          else
            Result := TMemberLevel.Instance;
        TIndexSymbolKind.Constructor_, TIndexSymbolKind.Variable:
          Result := TMemberLevel.Instance;
        TIndexSymbolKind.Routine:
          Result := TMemberLevel.NotMember;
      else
        // Konstanten, Aufzählungswerte und Typen der Klasse.
        Result := TMemberLevel.StaticLevel;
      end;
    end;
  Result.InterfaceMember :=
    function(const ATypeName, AName: string; AOffset: Integer): Boolean
    var
      Resolved: TResolvedSymbol;
    begin
      Resolved := AResolver.ResolveChain(ATree, FileName, HeadName(ATypeName).Split(['.']), AOffset);
      if not Resolved.Found then
        Exit(Fallback.InterfaceMember(ATypeName, AName, AOffset));
      Result := (Resolved.SymbolKind = TIndexSymbolKind.InterfaceType) and AResolver.ResolveChain(ATree, FileName,
        [HeadName(ATypeName), AName], AOffset).Found;
    end;
  Result.VisibleHelper :=
    function(const ATypeName: string; AOffset: Integer): string
    var
      Helper: TResolvedSymbol;
    begin
      if AResolver.VisibleHelper(ATree, FileName, ATypeName, AOffset, Helper) then
        Exit(Helper.Name);
      Result := Fallback.VisibleHelper(ATypeName, AOffset);
    end;
  Result.NameVisible :=
    function(const AName: string; AOffset: Integer): Boolean
    begin
      Result := AResolver.ResolveChain(ATree, FileName, [AName], AOffset).Found;
    end;
end;

{ TMethodTarget }

function TMethodTarget.Conversions: TArray<TMethodConversion>;
begin
  Result := [TMethodConversion.ClassMethod, TMethodConversion.ClassMethodCalls];
  if RoutineReason = '' then
    Result := Result + [TMethodConversion.Routine];
  if HelperReason = '' then
    Result := Result + [TMethodConversion.Helper];
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
    function CheckDeclaration(out AReason: string): Boolean;
    function ScanNames(out AReason: string): Boolean;
    function CheckLocalUses(out AReason: string): Boolean;
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

function TMethodPlan.Analyze(AOffset: Integer; out AReason: string): Boolean;
var
  Found, Index, First, Last: Integer;
  Section: TSyntaxNode;
begin
  Result := False;
  AReason := '';
  if (Tree = nil) or (Tree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Routine := TRoutineParts.TopRoutineAt(Tree, AOffset, Declaration);
  if (Routine = nil) or (Routine.Parent = nil) or (Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
    Exit(Fail('keine Methode mit Rumpf in dieser Unit', AReason));
  Header := TRoutineParts.HeaderOf(Routine);
  Body := TRoutineBody.BodyOf(Routine);
  if (Header = nil) or (Body = nil) then
    Exit(Fail('Methode ohne Rumpf', AReason));
  Target.Name := TRoutineBody.ShortNameOf(Routine.Name);
  Target.ClassName := TRoutineBody.QualifierOf(Routine.Name);
  if Target.ClassName = '' then
    Exit(Fail('keine Methode', AReason));
  if (Pos('<', Target.ClassName) > 0) or (Pos('.', Target.ClassName) > 0) then
    Exit(Fail('Methode eines generischen oder verschachtelten Typs', AReason));
  Index := TRoutineBody.TokenAt(Tokens, Header.StartOffset);
  if (Index <= High(Tokens)) and (Tokens[Index].IsKeyword('constructor') or Tokens[Index].IsKeyword('destructor') or
    Tokens[Index].IsKeyword('operator')) then
    Exit(Fail('Konstruktor, Destruktor oder Operator', AReason));
  if TRoutineParts.IsClassHeader(Tokens, Header) then
    Exit(Fail('schon eine class-Methode', AReason));
  if TRoutineParts.HasWord(Tokens, Header, ['forward', 'external', 'assembler']) then
    Exit(Fail('nicht unterstützte Form', AReason));
  TypeBody := TRoutineBody.TypeBody(Tree.Root, Target.ClassName);
  if (TypeBody = nil) or not (TypeBody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
    Exit(Fail('Klasse ' + Target.ClassName + ' nicht in der Datei', AReason));
  Target.IsRecord := TypeBody.Kind = TSyntaxKind.RecordType;
  Found := 0;
  Declaration := nil;
  for Index := 0 to TypeBody.ChildCount - 1 do
    if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and not TypeBody[Index].IsMethodResolution and
      SameText(TypeBody[Index].Name, Target.Name) then
    begin
      Inc(Found);
      Declaration := TypeBody[Index];
    end;
  if Found > 1 then
    Exit(Fail('überladen', AReason));
  if Declaration = nil then
    Exit(Fail('Deklaration fehlt', AReason));
  Visibility := TRoutineBody.VisibilityOf(TypeBody, Declaration);
  Section := Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  ClassInInterface := (Section <> nil) and TRoutineBody.Within(TypeBody, Section);
  IsFunction := TRoutineParts.IsFunction(Routine);
  Parameters := TRoutineParts.ParameterTexts(Text, Declaration);
  if (Parameters = nil) and (Declaration.FindChild(TSyntaxKind.Parameters) <> nil) and
    (Declaration.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
    Exit(Fail('nicht unterstützte Parameter', AReason));
  if not CheckDeclaration(AReason) or not ScanNames(AReason) or not CheckLocalUses(AReason) then
    Exit;
  if not TRoutineParts.NameTokens(Tokens, Header, First, Last) then
    Exit(Fail('Name im Kopf nicht gefunden', AReason));
  Target.NamePosition := Tokens[Last].StartPos;
  Target.HeaderEnd := Header.EndPos;
  CheckRoutine;
  CheckHelper;
  Result := True;
end;

function TMethodPlan.CheckDeclaration(out AReason: string): Boolean;
var
  Index, Token: Integer;
  Child: TSyntaxNode;
  InClause: Boolean;
begin
  Result := False;
  if TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message',
    'reintroduce', 'final']) then
    Exit(Fail('virtuell, override oder Botschaft', AReason));
  for Index := 0 to TypeBody.ChildCount - 1 do
  begin
    Child := TypeBody[Index];
    // Methodenzuordnung "procedure IFoo.Bar = Name".
    if (Child.Kind = TSyntaxKind.RoutineHeader) and Child.IsMethodResolution and
      SameText(Child.ResolutionTarget, Target.Name) then
      Exit(Fail('Methode eines Interfaces (' + Child.Name + ')', AReason));
    // Vorfahrenliste: Interfaces, deren Mitglied die Methode ist.
    if (Child.Kind = TSyntaxKind.TypeReference) and Assigned(Lookup.InterfaceMember) and
      Lookup.InterfaceMember(Child.Name, Target.Name, Child.StartOffset) then
      Exit(Fail('gehört zum Interface ' + Child.Name, AReason));
    if Child.Kind = TSyntaxKind.PropertyDecl then
    begin
      InClause := False;
      Token := TRoutineBody.TokenAt(Tokens, Child.StartOffset);
      while (Token <= High(Tokens)) and (Tokens[Token].Offset < Child.EndOffset) do
      begin
        if MatchText(Tokens[Token].Text, ['read', 'write', 'stored']) then
          InClause := True
        else if InClause and SameText(Tokens[Token].Text, Target.Name) then
          Exit(Fail('Zugriffsmethode der Property ' + Child.Name, AReason));
        Inc(Token);
      end;
    end;
  end;
  if Assigned(Lookup.InForm) and Lookup.InForm(Target.Name) then
    Exit(Fail('steht als Ereignis in der Formulardatei', AReason));
  Result := True;
end;

function TMethodPlan.ScanNames(out AReason: string): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Level: TMemberLevel;
  Visible: TIndexVisibility;
  Index: Integer;
  InHead: Boolean;
begin
  Result := False;
  Statics := nil;
  if not Assigned(Lookup.MemberLevel) then
    Exit(Fail('Namen nicht auflösbar', AReason));
  Index := TRoutineBody.TokenAt(Tokens, Routine.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Routine.EndOffset) do
  begin
    if Tokens[Index].IsKeyword('inherited') then
      Exit(Fail('benutzt inherited', AReason));
    Inc(Index);
  end;
  if TRoutineLocals.HasKind(Routine, TSyntaxKind.WithStatement) then
    Exit(Fail('benutzt with', AReason));
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.Identifier, Nodes);
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, Nodes);
    // Typen im Kopf der Deklaration gelten in der Klasse.
    TRoutineLocals.CollectKind(Declaration, TSyntaxKind.TypeReference, Nodes);
    for Node in Nodes do
    begin
      InHead := TRoutineBody.Within(Node, Declaration) or TRoutineBody.Within(Node, Header);
      if (Node.Kind = TSyntaxKind.TypeReference) and TRoutineBody.Within(Node, Header) then
        Continue;
      if (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, 'Self') then
        Exit(Fail(Format('benutzt Self (%s)', [Where('', Node.StartPos.Line)]), AReason));
      if (Node.Kind = TSyntaxKind.TypeReference) and (Pos('.', Node.Name) > 0) then
        Continue;
      if not InHead and TRoutineParts.Shadowed(Cache, Node, Routine, HeadName(Node.Name), True) then
        Continue;
      Level := Lookup.MemberLevel(Node, Visible);
      // Ein Typname ist nie ein Instanzmitglied; unbekannte Typen ändern nichts.
      if (Node.Kind = TSyntaxKind.TypeReference) and (Level in [TMemberLevel.Instance, TMemberLevel.Unknown]) then
        Level := TMemberLevel.NotMember;
      case Level of
        TMemberLevel.Instance:
          Exit(Fail(Format('benutzt %s (%s)', [Node.Name, Where('', Node.StartPos.Line)]), AReason));
        TMemberLevel.Unknown:
          Exit(Fail(Format('%s ist unbekannt (%s)', [HeadName(Node.Name), Where('', Node.StartPos.Line)]),
            AReason));
        TMemberLevel.ClassLevel, TMemberLevel.StaticLevel:
          begin
            if Level = TMemberLevel.ClassLevel then
              UsesClassLevel := True;
            if InHead then
              HeadUsesClassType := True
            else
              Statics := Statics + [Node];
            if (StrictName = '') and (Visible in [TIndexVisibility.StrictPrivate,
              TIndexVisibility.StrictProtected]) then
              StrictName := HeadName(Node.Name);
          end;
      end;
    end;
  finally
    Nodes.Free;
  end;
  Result := True;
end;

function TMethodPlan.CheckLocalUses(out AReason: string): Boolean;
var
  Index: Integer;
  Implementation_, Other: TSyntaxNode;
  Uses_: TList<TSyntaxNode>;
  Node, Callee, Call: TSyntaxNode;
  Use: TMethodUse;
begin
  // In den Methoden der Klasse: Methodenzeiger ohne Self. davor (OnClick := Name) sieht schon die Datei.
  Result := False;
  Implementation_ := Routine.Parent;
  Uses_ := TList<TSyntaxNode>.Create;
  try
    for Index := 0 to Implementation_.ChildCount - 1 do
    begin
      Other := Implementation_[Index];
      if (Other.Kind <> TSyntaxKind.RoutineDecl) or not SameText(TRoutineBody.QualifierOf(Other.Name),
        Target.ClassName) then
        Continue;
      Uses_.Clear;
      TRoutineLocals.CollectKind(Other, TSyntaxKind.Identifier, Uses_);
      for Node in Uses_ do
      begin
        if not SameText(Node.Name, Target.Name) or TRoutineBody.Within(Node, TRoutineParts.HeaderOf(Other)) then
          Continue;
        Use := TMethodWithoutSelf.UseAt(Tree, Node.StartOffset, Target.Name, Callee, Call);
        if IsPointer(Use) then
          Exit(Fail(Format('wird als Methodenzeiger benutzt (%s)', [Where('', Node.StartPos.Line)]), AReason));
      end;
    end;
  finally
    Uses_.Free;
  end;
  Result := True;
end;

procedure TMethodPlan.CheckRoutine;
begin
  Target.RoutineReason := '';
  if StrictName <> '' then
    Target.RoutineReason := 'benutzt ' + StrictName + ' (strict)'
  else if HeadUsesClassType then
    Target.RoutineReason := 'der Kopf nennt einen Typ der Klasse'
  else if IndexText(Target.Name, TRoutineParts.UnitNames(Tree.Root)) >= 0 then
    Target.RoutineReason := Target.Name + ' gibt es schon in der Unit';
end;

function TMethodPlan.FirstParameterNodes: TArray<TSyntaxNode>;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Result := nil;
  if Parameters = nil then
    Exit;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
      if SameText(Node.Name, Parameters[0].Name) and not TRoutineParts.Shadowed(Cache, Node, Routine,
        Parameters[0].Name, False) then
        Result := Result + [Node];
  finally
    Nodes.Free;
  end;
end;

function TMethodPlan.FirstParameterUses(out AReason: string): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  AReason := '';
  for Node in FirstParameterNodes do
  begin
    // const schreibt der Compiler ohnehin nicht; ein Wertparameter würde als Self den Wert des Aufrufers ändern.
    if (Parameters[0].Modifier = '') and (TRoutineLocals.AccessOf(Node, Lookup.Flow) <> TLocalAccess.Read) then
      Exit(not Fail(Parameters[0].Name + ' wird geschrieben', AReason));
    if (Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.AddressOf) then
      Exit(not Fail('@' + Parameters[0].Name, AReason));
    if TRoutineParts.InAnonymous(Node, Routine) then
      Exit(not Fail(Parameters[0].Name + ' in einer anonymen Methode', AReason));
  end;
end;

procedure TMethodPlan.CheckHelper;
var
  TypeName, Reason: string;
begin
  Target.HelperReason := '';
  Target.HelperType := '';
  if StrictName <> '' then
    Target.HelperReason := 'benutzt ' + StrictName + ' (strict)'
  else if HeadUsesClassType then
    Target.HelperReason := 'der Kopf nennt einen Typ der Klasse';
  if Target.HelperReason <> '' then
    Exit;
  if Parameters = nil then
  begin
    Target.HelperReason := 'ohne Parameter';
    Exit;
  end;
  if not MatchText(Parameters[0].Modifier, ['', 'const']) then
  begin
    Target.HelperReason := 'erster Parameter ist ' + Parameters[0].Modifier;
    Exit;
  end;
  if (Parameters[0].Rest = '') or (Pos('=', Parameters[0].Rest) > 0) then
  begin
    Target.HelperReason := 'erster Parameter ohne Typ oder mit Vorgabewert';
    Exit;
  end;
  TypeName := Trim(Copy(Parameters[0].Rest, 3, MaxInt));
  if not TMethodWithoutSelf.IsSimpleType(TypeName) then
  begin
    Target.HelperReason := 'erster Parameter hat keinen einfachen Typ';
    Exit;
  end;
  if FirstParameterUses(Reason) then
  begin
    Target.HelperReason := Reason;
    Exit;
  end;
  Target.HelperType := TypeName;
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
    Names := TRoutineParts.UnitNames(Tree.Root);
end;

/// <summary>Bearbeitung, die ANode samt Zeile entfernt, wenn die Zeile sonst leer ist; sonst nur den Bereich.</summary>
function RemoveLine(const AText: string; const ALines: TLineTable; ANode: TSyntaxNode): TOffsetEdit;
var
  LineStart, NextStart: Integer;
begin
  LineStart := ALines.LineStart(ANode.StartPos.Line);
  NextStart := ALines.LineStart(ANode.EndPos.Line + 1);
  if ANode.EndPos.Line + 1 >= ALines.LineCount then
    NextStart := Length(AText);
  if (Trim(Copy(AText, LineStart + 1, ANode.StartOffset - LineStart)) = '') and
    (Trim(Copy(AText, ANode.EndOffset + 1, NextStart - ANode.EndOffset)) = '') then
    Result := TOffsetEdit.Create(LineStart, NextStart, '')
  else
    Result := TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, '');
end;

/// <summary>Direktiven der Deklaration, die mitkommen ("inline; stdcall;"), mit führendem Leerzeichen.</summary>
function KeptDirectives(const AText: string; ADeclaration: TSyntaxNode): string;
var
  Index: Integer;
  Child: TSyntaxNode;
begin
  Result := '';
  for Index := 0 to ADeclaration.ChildCount - 1 do
  begin
    Child := ADeclaration[Index];
    if (Child.Kind = TSyntaxKind.Directive) and (IndexText(Child.Name, DroppedDirectives) < 0) then
      Result := Result + ' ' + TRoutineBody.TextOf(AText, Child) + ';';
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
    function AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
    function DeclaringEdits(out AReason: string): Boolean;
    function ClassMethodEdits(out AReason: string): Boolean;
    function RoutineEdits(out AReason: string): Boolean;
    function HelperEdits(out AReason: string): Boolean;
    function QualifyStatics: TArray<TOffsetEdit>;
    function ChooseHelper(out AReason: string): Boolean;
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
    Warnings := Warnings + [AText];
end;

function TMethodBuild.AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
var
  Callee, Call, Receiver, First: TSyntaxNode;
  Use: TMethodUse;
  Line: Integer;
  Before, After, Rest, NewText: string;
  Edit: TOffsetEdit;
  Changed: Boolean;
begin
  Result := False;
  Line := AWork.Lines.PositionAt(AOffset).Line;
  Use := TMethodWithoutSelf.UseAt(AWork.Tree, AOffset, Plan.Target.Name, Callee, Call);
  if Plan.IsPointer(Use) then
    Exit(Fail(Where(AWork.FileName, Line) + ': als Methodenzeiger benutzt', AReason));
  case Use of
    TMethodUse.Inherited_:
      Exit(Fail(Where(AWork.FileName, Line) + ': inherited-Aufruf', AReason));
    TMethodUse.Accessor:
      Exit(Fail(Where(AWork.FileName, Line) + ': Zugriffsmethode einer Property', AReason));
    TMethodUse.Unknown:
      Exit(Fail(Where(AWork.FileName, Line) + ': Verwendung nicht erkannt', AReason));
  end;
  if AWork.Declaring and not TRoutineBody.Within(Callee, Plan.Routine) and (AOffset < FirstUse) then
    FirstUse := AOffset;
  if not AWork.Declaring then
    CalledOutside := True;
  Receiver := nil;
  if Callee.Kind = TSyntaxKind.MemberAccess then
    Receiver := Callee[0];
  Edit := TOffsetEdit.Create(0, 0, '');
  Changed := False;
  case Conversion of
    TMethodConversion.ClassMethodCalls:
      if (Receiver <> nil) and TRoutineBody.IsVariableChain(Receiver) and not ((Receiver.Kind =
        TSyntaxKind.Identifier) and SameText(Receiver.Name, 'Self')) then
      begin
        Edit := TOffsetEdit.Create(Receiver.StartOffset, Receiver.EndOffset, Plan.Target.ClassName);
        Changed := True;
      end;
    TMethodConversion.Routine:
      if Receiver <> nil then
      begin
        if not TRoutineBody.IsVariableChain(Receiver) then
          Warn(Format('%s: %s wird nicht mehr ausgewertet.', [Where(AWork.FileName, Line),
            TRoutineBody.TextOf(AWork.Text, Receiver)]));
        NewText := '';
        if not AWork.Declaring and (IndexText(Plan.Target.Name, AWork.Names) >= 0) then
          NewText := Plan.UnitName + '.';
        Edit := TOffsetEdit.Create(Receiver.StartOffset, AOffset, NewText);
        Changed := True;
      end
      else if not AWork.Declaring and (IndexText(Plan.Target.Name, AWork.Names) >= 0) then
      begin
        Edit := TOffsetEdit.Create(AOffset, AOffset, Plan.UnitName + '.');
        Changed := True;
      end;
    TMethodConversion.Helper:
      begin
        if (Call = nil) or (Call.ChildCount < 2) then
          Exit(Fail(Where(AWork.FileName, Line) + ': Aufruf ohne Argumente', AReason));
        if (Receiver <> nil) and not TRoutineBody.IsVariableChain(Receiver) then
          Warn(Format('%s: %s wird nicht mehr ausgewertet.', [Where(AWork.FileName, Line),
            TRoutineBody.TextOf(AWork.Text, Receiver)]));
        First := Call[1];
        NewText := TRoutineBody.TextOf(AWork.Text, First);
        if not TRoutineBody.IsVariableChain(First) then
          NewText := '(' + NewText + ')';
        NewText := NewText + '.' + Plan.Target.Name;
        if Call.ChildCount > 2 then
        begin
          Rest := Copy(AWork.Text, Call[2].StartOffset + 1, Call[Call.ChildCount - 1].EndOffset -
            Call[2].StartOffset);
          NewText := NewText + '(' + Rest + ')';
        end;
        Edit := TOffsetEdit.Create(Call.StartOffset, Call.EndOffset, NewText);
        Changed := True;
      end;
  end;
  if Changed then
  begin
    AWork.Edits := AWork.Edits + [Edit];
    if not AWork.Declaring then
      AWork.NeedsUses := True;
    Inc(Calls);
    if AWork.Lines.PositionAt(Edit.Start).Line = AWork.Lines.PositionAt(Edit.Stop).Line then
    begin
      Before := LineText(AWork.Text, AWork.Lines, Line);
      After := TRoutineParts.ApplyEdits(Before, AWork.Lines.LineStart(Line), [Edit]);
      PreviewLines := PreviewLines + [Format('%s: %s → %s', [Where(AWork.FileName, Line), Trim(Before),
        Trim(After)])];
    end;
  end
  else if (Conversion in [TMethodConversion.Routine, TMethodConversion.Helper]) and not AWork.Declaring then
    AWork.NeedsUses := True;
  Result := True;
end;

function TMethodBuild.QualifyStatics: TArray<TOffsetEdit>;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  for Node in Plan.Statics do
    Result := Result + [TOffsetEdit.Create(Node.StartOffset, Node.StartOffset, Plan.Target.ClassName + '.')];
end;

function TMethodBuild.ClassMethodEdits(out AReason: string): Boolean;
var
  Work: TFileWork;
  WithStatic: Boolean;
begin
  Work := Works[0];
  WithStatic := StaticWanted or Plan.Target.IsRecord;
  if WithStatic and Plan.UsesClassLevel and not Plan.Target.IsRecord then
  begin
    WithStatic := False;
    Warn(Format('%s bleibt ohne static: Der Rumpf ruft class-Methoden ohne static auf.', [Plan.Target.Name]));
  end;
  Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Declaration.StartOffset, Plan.Declaration.StartOffset,
    'class '), TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.StartOffset, 'class ')];
  if WithStatic then
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Declaration.EndOffset, Plan.Declaration.EndOffset,
      ' static;')];
  Result := True;
end;

/// <summary>Bearbeitungen, die AInner (im Bereich AStart..AStop) in den verschobenen Text übernehmen; die übrigen
/// bleiben in AEdits.</summary>
function SplitEdits(var AEdits: TArray<TOffsetEdit>; AStart, AStop: Integer): TArray<TOffsetEdit>;
var
  Kept: TArray<TOffsetEdit>;
  Edit: TOffsetEdit;
begin
  Result := nil;
  Kept := nil;
  for Edit in AEdits do
    if (Edit.Start >= AStart) and (Edit.Stop <= AStop) then
      Result := Result + [Edit]
    else
      Kept := Kept + [Edit];
  AEdits := Kept;
end;

/// <summary>Oberste Routine der Implementierung, die AOffset enthält; nil ohne.</summary>
function TopLevelAt(AImplementation: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AImplementation.ChildCount - 1 do
    if (AImplementation[Index].Kind = TSyntaxKind.RoutineDecl) and
      TRoutineParts.Encloses(AImplementation[Index], AOffset) then
      Exit(AImplementation[Index]);
end;

/// <summary>Bereich der Routine samt Kommentaren darüber bis zum Anfang der Folgezeile, dazu eine Leerzeile
/// dahinter.</summary>
procedure RoutineSpan(const AText: string; const ALines: TLineTable; ARoutine: TSyntaxNode; out AStart,
  AStop: Integer);
var
  Next: Integer;
begin
  AStart := ALines.LineStart(TRoutineBody.RoutineInsertLine(AText, ARoutine));
  Next := ARoutine.EndPos.Line + 1;
  AStop := ALines.LineStart(Next);
  if Next >= ALines.LineCount then
    AStop := Length(AText)
  else if Trim(LineText(AText, ALines, Next)) = '' then
    AStop := ALines.LineStart(Next + 1);
end;

function TMethodBuild.RoutineEdits(out AReason: string): Boolean;
var
  Work: TFileWork;
  Head, Moved: string;
  Implementation_, First: TSyntaxNode;
  Start, Stop, InsertAt, Line: Integer;
  Inner: TArray<TOffsetEdit>;
begin
  Result := False;
  Work := Works[0];
  if CalledOutside and not Plan.ClassInInterface then
    Exit(Fail('andere Units rufen auf, die Klasse steht aber im implementation-Teil', AReason));
  Head := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, Plan.Parameters, False);
  Work.Edits := Work.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  if CalledOutside then
  begin
    // Vor implementation, mit Leerzeile.
    Line := Plan.Routine.Parent.StartPos.Line;
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(Line), Plan.Lines.LineStart(Line),
      Head + KeptDirectives(Plan.Text, Plan.Declaration) + LineBreak + LineBreak)];
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset, Head)];
  end
  else
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
      Head + KeptDirectives(Plan.Text, Plan.Declaration))];
  Work.Edits := Work.Edits + QualifyStatics;
  // Ohne Deklaration im interface muss die Routine vor ihrer ersten Verwendung stehen.
  if not CalledOutside and (FirstUse < Plan.Routine.StartOffset) then
  begin
    Implementation_ := Plan.Routine.Parent;
    First := TopLevelAt(Implementation_, FirstUse);
    if First = nil then
      Exit(Fail('erste Verwendung nicht in einer Routine', AReason));
    RoutineSpan(Plan.Text, Plan.Lines, Plan.Routine, Start, Stop);
    Inner := SplitEdits(Work.Edits, Start, Stop);
    Moved := TRoutineParts.ApplyEdits(Copy(Plan.Text, Start + 1, Stop - Start), Start, Inner);
    if not EndsStr(LineBreak + LineBreak, Moved) then
      Moved := Moved + LineBreak;
    InsertAt := Plan.Lines.LineStart(TRoutineBody.RoutineInsertLine(Plan.Text, First));
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Start, Stop, ''), TOffsetEdit.Create(InsertAt, InsertAt, Moved)];
  end;
  Result := True;
end;

function TMethodBuild.ChooseHelper(out AReason: string): Boolean;
var
  Found: TSyntaxNode;
  Interface_: TSyntaxNode;
  TypeName, Base, Visible: string;
  Taken: TArray<string>;
begin
  Result := False;
  TypeName := Plan.Target.HelperType;
  Found := Plan.Tree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.HelperType) and SameText(ANode.Name, 'record') and (ANode.ChildCount > 0) and
        (ANode[0].Kind = TSyntaxKind.TypeReference) and SameTypeName(HeadName(ANode[0].Name), TypeName) then
        Result := TSyntaxSearchStep.Found;
    end);
  Interface_ := Plan.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  Visible := '';
  if Assigned(Plan.Lookup.VisibleHelper) then
    Visible := Plan.Lookup.VisibleHelper(TypeName, Plan.Routine.StartOffset);
  if Found <> nil then
  begin
    if CalledOutside and ((Interface_ = nil) or not TRoutineBody.Within(Found, Interface_)) then
      Exit(Fail(Format('der Helper %s steht im implementation-Teil, andere Units rufen aber auf',
        [Found.Parent.Name]), AReason));
    HelperNode := Found;
    HelperName := Found.Parent.Name;
  end
  else
  begin
    if CalledOutside and not Plan.ClassInInterface then
      Exit(Fail('andere Units rufen auf, die Klasse steht aber im implementation-Teil', AReason));
    Taken := TRoutineParts.UnitNames(Plan.Tree.Root);
    Base := TMethodWithoutSelf.HelperNameFor(TypeName);
    // Den Namen eines sichtbaren Helpers (TStringHelper der RTL) nicht verdecken: THauptStringHelper.
    if SameText(Base, Visible) or (Assigned(Plan.Lookup.NameVisible) and Plan.Lookup.NameVisible(Base,
      Plan.Routine.StartOffset)) then
      Base := 'T' + Capitalized(Plan.UnitName.Substring(Plan.UnitName.LastIndexOf('.') + 1)) + Copy(Base, 2,
        MaxInt);
    HelperName := TRoutineParts.FreeName(Base, Taken);
  end;
  if (Visible <> '') and not SameText(Visible, HelperName) then
    Warn(Format('Für %s ist schon %s sichtbar. Nur ein Helper je Typ wirkt: Wo %s gilt, sind die Methoden von ' +
      '%s nicht mehr erreichbar.', [TypeName, Visible, HelperName, Visible]));
  Result := True;
end;

function TMethodBuild.HelperEdits(out AReason: string): Boolean;
var
  Work: TFileWork;
  Rest: TArray<TParameterText>;
  Decl, Indent, Inner, Block: string;
  Node, Implementation_, Clause, TypeDecl: TSyntaxNode;
  Index, EndToken, Line, At: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Result := False;
  if not ChooseHelper(AReason) then
    Exit;
  Work := Works[0];
  Tokens := Plan.Tokens;
  Rest := Copy(Plan.Parameters, 1, MaxInt);
  Decl := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, Rest, False) +
    KeptDirectives(Plan.Text, Plan.Declaration);
  Inner := TRoutineBody.IndentUnit(Style);
  Work.Edits := Work.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  if HelperNode <> nil then
  begin
    // Vor das end des Helpers.
    EndToken := -1;
    Index := TRoutineBody.TokenAt(Tokens, HelperNode.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < HelperNode.EndOffset) do
    begin
      if Tokens[Index].IsKeyword('end') then
        EndToken := Index;
      Inc(Index);
    end;
    if EndToken < 0 then
      Exit(Fail('Ende des Helpers nicht gefunden', AReason));
    Line := Tokens[EndToken].StartPos.Line;
    if Trim(Copy(LineText(Plan.Text, Plan.Lines, Line), 1, Tokens[EndToken].StartPos.Character)) <> '' then
      Exit(Fail('end des Helpers steht nicht allein in der Zeile', AReason));
    Indent := IndentAt(Plan.Text, Plan.Lines, Line) + Inner;
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(Line), Plan.Lines.LineStart(Line),
      Indent + Decl + LineBreak)];
  end
  else if CalledOutside then
  begin
    // Hinter die Klasse, im selben type-Abschnitt.
    TypeDecl := Plan.TypeBody.Parent;
    Indent := IndentAt(Plan.Text, Plan.Lines, TypeDecl.StartPos.Line);
    Block := LineBreak + Indent + HelperName + ' = record helper for ' + Plan.Target.HelperType + LineBreak +
      Indent + Inner + Decl + LineBreak + Indent + 'end;' + LineBreak;
    At := Plan.Lines.LineStart(TypeDecl.EndPos.Line + 1);
    if TypeDecl.EndPos.Line + 1 >= Plan.Lines.LineCount then
      At := Length(Plan.Text);
    Work.Edits := Work.Edits + [TOffsetEdit.Create(At, At, Block)];
  end
  else
  begin
    // Am Anfang von implementation, hinter dessen uses.
    Implementation_ := Plan.Routine.Parent;
    Clause := Implementation_.FindChild(TSyntaxKind.UsesClause);
    if Clause <> nil then
      Line := Clause.EndPos.Line + 1
    else
      Line := Implementation_.StartPos.Line + 1;
    Block := LineBreak + 'type' + LineBreak + Inner + HelperName + ' = record helper for ' +
      Plan.Target.HelperType + LineBreak + Inner + Inner + Decl + LineBreak + Inner + 'end;' + LineBreak;
    At := Plan.Lines.LineStart(Line);
    Work.Edits := Work.Edits + [TOffsetEdit.Create(At, At, Block)];
  end;
  Work.Edits := Work.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
    TRoutineParts.HeadText(Plan.Text, Plan.Declaration, HelperName + '.' + Plan.Target.Name, Rest, False))];
  Work.Edits := Work.Edits + QualifyStatics;
  for Node in Plan.FirstParameterNodes do
    Work.Edits := Work.Edits + [TOffsetEdit.Create(Node.StartOffset, Node.EndOffset, 'Self')];
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
    Result := ClassMethodEdits(AReason);
  end;
end;

/// <summary>Überschneiden sich zwei Bearbeitungen (gleiche Einfügestelle zählt nicht)?</summary>
function Overlapping(const AEdits: TArray<TOffsetEdit>): Boolean;
var
  Index, Other: Integer;
begin
  for Index := 0 to High(AEdits) do
    for Other := Index + 1 to High(AEdits) do
      if (AEdits[Index].Start < AEdits[Other].Stop) and (AEdits[Other].Start < AEdits[Index].Stop) then
        Exit(True);
  Result := False;
end;

function TMethodBuild.Finish(out AResult: TMethodResult; out AReason: string): Boolean;
var
  Work: TFileWork;
  Item: TMethodFileEdits;
  Edit: TOffsetEdit;
  UsesEdits: TArray<TTextEdit>;
  Added: TArray<string>;
  NewText: string;
  Tree: TSyntaxTree;
  Action: string;
begin
  Result := False;
  AResult := Default(TMethodResult);
  for Work in Works do
  begin
    if Overlapping(Work.Edits) then
      Exit(Fail(Where(Work.FileName, 0) + ': verschachtelte Aufrufe', AReason));
    Item.FileName := Work.FileName;
    Item.Edits := nil;
    for Edit in Work.Edits do
      Item.Edits := Item.Edits + [TTextEdit.Create(TTextRange.Create(Work.Lines.PositionAt(Edit.Start),
        Work.Lines.PositionAt(Edit.Stop)), Edit.Text)];
    if Work.NeedsUses and TUsesActions.AddUnits(Work.Tree.Tokens, [Plan.UnitName], nil, nil,
      TTextLines.LineBreakOf(Work.Text), UsesEdits, Added) then
      Item.Edits := Item.Edits + UsesEdits;
    if Item.Edits = nil then
      Continue;
    NewText := TChangeSignature.ApplyEdits(Work.Text, Item.Edits);
    Tree := TPascalParser.Parse(NewText);
    try
      if Length(Tree.Diagnostics) > Length(Work.Tree.Diagnostics) then
        Exit(Fail(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s)',
          [ExtractFileName(Work.FileName), Tree.Diagnostics[0].StartPos.Line + 1, Tree.Diagnostics[0].Message]),
          AReason));
    finally
      Tree.Free;
    end;
    AResult.Files := AResult.Files + [Item];
  end;
  case Conversion of
    TMethodConversion.Routine:
      Action := Format('%s.%s wird freie Routine', [Plan.Target.ClassName, Plan.Target.Name]);
    TMethodConversion.Helper:
      Action := Format('%s.%s wandert nach %s (record helper for %s)', [Plan.Target.ClassName, Plan.Target.Name,
        HelperName, Plan.Target.HelperType]);
  else
    Action := Format('%s.%s wird class-Methode', [Plan.Target.ClassName, Plan.Target.Name]);
  end;
  AResult.Preview := Action + Format(', %d geänderte Aufrufe.', [Calls]);
  if PreviewLines <> nil then
    AResult.Preview := AResult.Preview + sLineBreak + string.Join(sLineBreak, PreviewLines);
  AResult.Warnings := Warnings;
  AResult.Calls := Calls;
  Result := True;
end;

{ TMethodWithoutSelf }

class function TMethodWithoutSelf.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TMethodLookup; out ATarget: TMethodTarget; out AReason: string): Boolean;
var
  Plan: TMethodPlan;
begin
  ATarget := Default(TMethodTarget);
  AReason := '';
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Plan := TMethodPlan.Create(AText, ATree, ALookup);
  try
    Result := Plan.Analyze(Plan.Lines.OffsetAt(APosition), AReason);
    if Result then
      ATarget := Plan.Target;
  finally
    Plan.Free;
  end;
end;

class function TMethodWithoutSelf.Candidates(const AText: string; ATree: TSyntaxTree;
  const ALookup: TMethodLookup): TArray<TMethodTarget>;
var
  Implementation_, Routine, Header: TSyntaxNode;
  Index: Integer;
  Found: TMethodTarget;
  Reason: string;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Implementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Implementation_ = nil then
    Exit;
  for Index := 0 to Implementation_.ChildCount - 1 do
  begin
    Routine := Implementation_[Index];
    if (Routine.Kind <> TSyntaxKind.RoutineDecl) or (TRoutineBody.QualifierOf(Routine.Name) = '') then
      Continue;
    Header := TRoutineParts.HeaderOf(Routine);
    if (Header <> nil) and Target(AText, ATree, Header.EndPos, ALookup, Found, Reason) then
      Result := Result + [Found];
  end;
end;

class function TMethodWithoutSelf.UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string;
  out ACallee, ACall: TSyntaxNode): TMethodUse;
var
  Found: TSyntaxNode;
  InProperty, InInherited: Boolean;
  Offset: Integer;
  Name: string;
  Parent: TSyntaxNode;
begin
  ACallee := nil;
  ACall := nil;
  Found := nil;
  InProperty := False;
  InInherited := False;
  Offset := AOffset;
  Name := AName;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := (ANode.StartOffset <= Offset) and (Offset < ANode.EndOffset);
      if not Result then
        Exit;
      if ANode.Kind = TSyntaxKind.PropertyDecl then
        InProperty := True
      else if (ANode.Kind = TSyntaxKind.InheritedExpr) and SameText(ANode.Name, Name) then
        InInherited := True
      else if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.StartOffset = Offset) and SameText(ANode.Name, Name)
      then
        Found := ANode
      else if (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, Name) and
        (ANode.EndOffset = Offset + Length(Name)) then
        Found := ANode;
    end);
  if InProperty then
    Exit(TMethodUse.Accessor);
  if InInherited then
    Exit(TMethodUse.Inherited_);
  if Found = nil then
    Exit(TMethodUse.Unknown);
  ACallee := Found;
  Parent := Found.Parent;
  if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Call) and (Parent[0] = Found) then
  begin
    ACall := Parent;
    Result := TMethodUse.Call;
  end
  else if (Parent <> nil) and (Parent.Kind = TSyntaxKind.CallStatement) then
    Result := TMethodUse.Call
  else if (Parent <> nil) and (Parent.Kind = TSyntaxKind.AddressOf) then
    Result := TMethodUse.Pointer
  else
    Result := TMethodUse.Value;
end;

class function TMethodWithoutSelf.Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
  const APosition: TTextPosition; AConversion: TMethodConversion; AStatic: Boolean;
  const ALookup: TMethodLookup; const AStyle: TFormatStyle; out AResult: TMethodResult;
  out AReason: string): Boolean;
var
  Plan: TMethodPlan;
  Build: TMethodBuild;
  Source: TMethodSource;
  Work: TFileWork;
  Offset: Integer;
begin
  AResult := Default(TMethodResult);
  AReason := '';
  if (ADeclaring.Tree = nil) or (ADeclaring.Tree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Plan := TMethodPlan.Create(ADeclaring.Text, ADeclaring.Tree, ALookup);
  Build := TMethodBuild.Create(Plan);
  try
    if not Plan.Analyze(Plan.Lines.OffsetAt(APosition), AReason) then
      Exit(False);
    case AConversion of
      TMethodConversion.Routine:
        if Plan.Target.RoutineReason <> '' then
          Exit(Fail(Plan.Target.RoutineReason, AReason));
      TMethodConversion.Helper:
        if Plan.Target.HelperReason <> '' then
          Exit(Fail(Plan.Target.HelperReason, AReason));
    end;
    Build.Conversion := AConversion;
    Build.StaticWanted := AStatic;
    Build.Style := AStyle;
    Build.Works.Add(TFileWork.Create(ADeclaring, True));
    for Source in AOthers do
      if (Source.Tree <> nil) and not SameText(Source.FileName, ADeclaring.FileName) then
        Build.Works.Add(TFileWork.Create(Source, False));
    for Work in Build.Works do
      for Offset in Work.Offsets do
      begin
        // Deklaration und Kopf der Implementierung zählen nicht.
        if Work.Declaring and (TRoutineParts.Encloses(Plan.Declaration, Offset) or
          TRoutineParts.Encloses(Plan.Header, Offset)) then
          Continue;
        if not Build.AddSite(Work, Offset, AReason) then
          Exit(False);
      end;
    if not Build.DeclaringEdits(AReason) then
      Exit(False);
    Result := Build.Finish(AResult, AReason);
  finally
    Build.Free;
    Plan.Free;
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
  Item: TMethodConversion;
begin
  for Item := Low(TMethodConversion) to High(TMethodConversion) do
    if SameText(ConversionName(Item), AName) then
    begin
      AConversion := Item;
      Exit(True);
    end;
  AConversion := TMethodConversion.ClassMethod;
  Result := False;
end;

class function TMethodWithoutSelf.IsSimpleType(const ATypeName: string): Boolean;
begin
  Result := IndexText(Trim(ATypeName), SimpleTypes) >= 0;
end;

class function TMethodWithoutSelf.HelperNameFor(const ATypeName: string): string;
var
  Name: string;
begin
  Name := Trim(ATypeName);
  if (Length(Name) > 1) and (Name[1] = 'T') and CharInSet(Name[2], ['A'..'Z']) then
    Name := Copy(Name, 2, MaxInt);
  if SameText(Name, 'UnicodeString') then
    Name := 'String';
  Result := 'T' + Capitalized(Name) + 'Helper';
end;

end.
