unit Atlas.Common.Editing.PropertyFromAccessors;

// Property aus Getter und Setter (#682), Gegenstück zu #467: Hat eine Klasse
// Zugriffsmethoden ohne passende Property, legt Atlas die Property an.
//   - Getter: Funktion mit Präfix (Get, Is und Has nur mit Ergebnis Boolean,
//     eigene Präfixe), ohne Parameter oder nur mit Indexparametern. Setter:
//     Prozedur mit Präfix (Set, eigene Präfixe), Wertparameter ohne oder mit
//     const als letzter Parameter, davor dieselben Indexparameter. var- und
//     out-Parameter, Standardwerte, Klassenmethoden und überladene Namen
//     zählen nicht: Delphi nimmt sie nicht als Zugriffsmethoden.
//   - Getter und Setter gehören zusammen, wenn Name ohne Präfix, Typ und
//     Indexparameter übereinstimmen; sonst entsteht die Property nur aus dem
//     Getter. Indizierte Properties heißen in der Mehrzahl (GetItem →
//     Items), ist der Name vergeben, wie der Getter ohne Präfix.
//   - Keine Property, wenn die Klasse den Namen schon hat oder eine andere
//     Property die Zugriffsmethode schon benutzt.
//   - read FX statt read GetX, wenn der Getter nur "Result := FX;" enthält
//     und das Feld FX denselben Typ hat.
//   - Abschnitt: der sichtbarsten Zugriffsmethode, auf Wunsch mindestens
//     public bzw. published. Die Property kommt ans Ende des letzten solchen
//     Abschnitts, der hinter den Zugriffsmethoden endet; sonst in einen neuen
//     Abschnitt vor "end" (Delphi verlangt die Methoden davor).
//   - Verbergen: Zugriffsmethoden, die der Aufrufer freigibt, wandern in einen
//     private- bzw. protected-Abschnitt vor der Property (nicht virtuelle,
//     abstrakte, überschriebene oder message-Methoden).
//   - Aufrufe: UseOf ordnet eine Verwendung ein, CallEdit stellt sie um
//     (X.GetCaption → X.Caption, X.SetCaption(V) → X.Caption := V,
//     X.GetItem(I) → X.Items[I]). Die Suche über das Projekt und die
//     Typprüfung bei unklaren Fällen macht Atlas.Common.Lsp.PropertyFromAccessors.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Sichtbarkeit eines Klassenabschnitts, aufsteigend.</summary>
  TMemberSection = (Private_, Protected_, Public_, Published_);
  /// <summary>Abschnitt der neuen Property: wie die sichtbarste Zugriffsmethode oder mindestens public bzw.
  /// published.</summary>
  TPropertySectionChoice = (Accessor, Public_, Published_);
  /// <summary>Zugriffsmethoden nach dem Anlegen verbergen: nie, nach private oder nach protected.</summary>
  TAccessorHiding = (Off, Private_, Protected_);
  /// <summary>Aufrufe umstellen: nachfragen (zwei Aktionen), immer oder nie.</summary>
  TReplaceCalls = (Ask, Always, Never);
  /// <summary>Verwendung einer Zugriffsmethode: Aufruf (umstellbar), Methodenzeiger (bleibt), unklar (Typ des
  /// Ziels entscheidet), bleibt (Property-Klausel, inherited, Anweisung ohne Wert).</summary>
  TAccessorUse = (Call, Pointer_, Unclear, Keep);
  {$SCOPEDENUMS OFF}

  TPropertyFromAccessorsOptions = record
    /// <summary>Präfixe der Zugriffsmethoden; Is und Has nur für Boolean-Getter, Set nur für Setter, Get nur für
    /// Getter.</summary>
    Prefixes: TArray<string>;
    Section: TPropertySectionChoice;
    Hiding: TAccessorHiding;
    class function Default: TPropertyFromAccessorsOptions; static;
    /// <summary>Aus den Werten der Einstellungen (accessor/public/published, off/private/protected); unbekannte
    /// Werte wie Default.</summary>
    class function FromNames(const APrefixes: TArray<string>; const ASection, AHiding: string):
      TPropertyFromAccessorsOptions; static;
  end;

  TAccessorMethod = record
    Name: string;
    /// <summary>Position des Namens in der Deklaration; Line -1 ohne Methode.</summary>
    NamePos: TTextPosition;
    /// <summary>Erste Zeile (samt Doku-Kommentaren direkt darüber) und letzte Zeile der Deklaration.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    Section: TMemberSection;
    /// <summary>virtual, dynamic, override, abstract, reintroduce oder message: bleibt in ihrem Abschnitt.</summary>
    Virtual_: Boolean;
    function Exists: Boolean;
  end;

  TAccessorProperty = record
    ClassName: string;
    /// <summary>Zeile der Klassen-Kopfzeile.</summary>
    ClassLine: Integer;
    Name: string;
    TypeName: string;
    /// <summary>Indexparameter ohne Klammern ("AIndex: Integer"); '' ohne.</summary>
    IndexParameters: string;
    IndexCount: Integer;
    Getter: TAccessorMethod;
    Setter: TAccessorMethod;
    /// <summary>Feld für "read", wenn der Getter es nur liefert; sonst ''.</summary>
    ReadField: string;
    function IsIndexed: Boolean;
    /// <summary>"property Caption: string read GetCaption write SetCaption;"</summary>
    function Declaration: string;
    /// <summary>Abschnitt der Property nach AChoice.</summary>
    function Section(AChoice: TPropertySectionChoice): TMemberSection;
  end;

  TPropertyFromAccessors = class
  public
    /// <summary>Alle fehlenden Properties der Klassen in ATree.</summary>
    class function Find(ATree: TSyntaxTree; const AText: string;
      const AOptions: TPropertyFromAccessorsOptions): TArray<TAccessorProperty>; static;
    /// <summary>Auf der Deklaration einer Zugriffsmethode deren Property, auf der Kopfzeile einer Klasse alle
    /// fehlenden (AWholeClass True); sonst leer.</summary>
    class function At(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const AOptions: TPropertyFromAccessorsOptions; out AWholeClass: Boolean): TArray<TAccessorProperty>; static;
    /// <summary>Darf AMethod nach AOptions.Hiding wandern (weniger sichtbar als jetzt, nicht virtuell)?</summary>
    class function CanHide(const AMethod: TAccessorMethod; const AOptions: TPropertyFromAccessorsOptions): Boolean;
      static;
    /// <summary>Änderungen in der Datei der Klasse: Properties anlegen, Zugriffsmethoden aus AHidden (Namen)
    /// verbergen.</summary>
    class function Edits(ATree: TSyntaxTree; const AText: string; const AProperties: TArray<TAccessorProperty>;
      const AHidden: TArray<string>; const AOptions: TPropertyFromAccessorsOptions): TArray<TTextEdit>; static;
    /// <summary>Verwendung des Bezeichners ANameToken (Getter bzw. Setter).</summary>
    class function UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer; AIsGetter: Boolean):
      TAccessorUse; static;
    /// <summary>Token vor einem unklaren Getter: das Ziel der Zuweisung bzw. der Name des Aufrufs, dem er als
    /// Argument dient; AArgument ist dann dessen Stelle (ab 0), sonst -1. -1, wenn es keins gibt.</summary>
    class function UnclearTarget(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      out AArgument: Integer): Integer; static;
    /// <summary>Aufruf bei ANameToken auf die Property umstellen; False, wenn die Zahl der Argumente nicht passt.
    /// Die Änderungen lassen die Argumente selbst aus, damit Aufrufe darin eigene Änderungen bekommen können.
    /// </summary>
    class function CallEdit(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      const AProperty: TAccessorProperty; AIsGetter: Boolean; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Steht ANameToken im Kopf einer Routine (Deklaration oder Implementierung)?</summary>
    class function IsHeaderName(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Boolean; static;
    /// <summary>private, protected, public, published.</summary>
    class function SectionName(ASection: TMemberSection): string; static;
    /// <summary>Mehrzahl eines Namens: Item → Items, Entry → Entries, Box → Boxes.</summary>
    class function Plural(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines;

const
  VirtualDirectives: array[0..5] of string = ('virtual', 'dynamic', 'override', 'abstract', 'reintroduce', 'message');
  StatementStarts: array[0..8] of string = (';', 'begin', 'then', 'else', 'do', 'try', 'finally', 'except', 'repeat');
  StatementEnds: array[0..5] of string = (';', 'end', 'else', 'until', 'except', 'finally');

{ Tokens }

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
  if Result > High(ATokens) then
    Result := -1;
end;

function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function IsSymbolAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ASymbol: string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and ATokens[AIndex].IsSymbol(ASymbol);
end;

function IsWordAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AWords: array of string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and
    (ATokens[AIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword, TPascalTokenKind.Symbol]) and
    (IndexText(ATokens[AIndex].Text, AWords) >= 0);
end;

/// <summary>Schließende Klammer zu AOpen ("(" oder "["); -1 ohne.</summary>
function Closing(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if IsSymbolAt(ATokens, Result, '(') or IsSymbolAt(ATokens, Result, '[') then
      Inc(Depth)
    else if IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Öffnende Klammer zu AClose (")" oder "]"); -1 ohne.</summary>
function Opening(const ATokens: TArray<TPascalToken>; AClose: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AClose;
  while Result >= 0 do
  begin
    if IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') then
      Inc(Depth)
    else if IsSymbolAt(ATokens, Result, '(') or IsSymbolAt(ATokens, Result, '[') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
    Dec(Result);
  end;
end;

/// <summary>Hinter einem generischen Namen (Foo&lt;T&gt;) das Token nach "&gt;"; sonst AIndex.</summary>
function SkipGenericArgs(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth: Integer;
begin
  Result := AIndex;
  if not IsSymbolAt(ATokens, AIndex, '<') then
    Exit;
  Depth := 0;
  while Result <= High(ATokens) do
  begin
    if IsSymbolAt(ATokens, Result, '<') then
      Inc(Depth)
    else if IsSymbolAt(ATokens, Result, '>') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(NextToken(ATokens, Result));
    end
    else if IsSymbolAt(ATokens, Result, ';') or IsSymbolAt(ATokens, Result, ':=') then
      Exit(AIndex);
    Inc(Result);
  end;
  Result := AIndex;
end;

/// <summary>Erstes Token des Ausdrucks A.B[1].C(2).Name, dessen Name bei ANameToken steht.</summary>
function ChainStart(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Integer;
var
  Dot, Part: Integer;
begin
  Result := ANameToken;
  Dot := PreviousToken(ATokens, Result);
  while IsSymbolAt(ATokens, Dot, '.') do
  begin
    Part := PreviousToken(ATokens, Dot);
    while IsSymbolAt(ATokens, Part, ')') or IsSymbolAt(ATokens, Part, ']') do
    begin
      Part := Opening(ATokens, Part);
      if Part < 0 then
        Exit;
      // Name vor der Klammer (Aufruf, Index); ohne Name ist die Klammer der Anfang.
      if (PreviousToken(ATokens, Part) >= 0) and
        (ATokens[PreviousToken(ATokens, Part)].Kind = TPascalTokenKind.Identifier) then
        Part := PreviousToken(ATokens, Part)
      else if IsSymbolAt(ATokens, PreviousToken(ATokens, Part), ')') or
        IsSymbolAt(ATokens, PreviousToken(ATokens, Part), ']') then
        Part := PreviousToken(ATokens, Part)
      else
        Break;
    end;
    if Part < 0 then
      Exit;
    Result := Part;
    Dot := PreviousToken(ATokens, Result);
  end;
end;

/// <summary>Kommas der obersten Ebene zwischen AOpen und AClose.</summary>
function TopLevelCommas(const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<Integer>;
var
  Index, Depth: Integer;
begin
  Result := nil;
  Depth := 0;
  Index := NextToken(ATokens, AOpen);
  while (Index >= 0) and (Index < AClose) do
  begin
    if IsSymbolAt(ATokens, Index, '(') or IsSymbolAt(ATokens, Index, '[') then
      Inc(Depth)
    else if IsSymbolAt(ATokens, Index, ')') or IsSymbolAt(ATokens, Index, ']') then
      Dec(Depth)
    else if (Depth = 0) and IsSymbolAt(ATokens, Index, ',') then
      Result := Result + [Index];
    Index := NextToken(ATokens, Index);
  end;
end;

{ Text }

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Leerraum zusammenfassen.</summary>
function Collapse(const AText: string): string;
begin
  Result := Trim(TRegEx.Replace(AText, '\s+', ' '));
end;

{ TPropertyFromAccessorsOptions }

class function TPropertyFromAccessorsOptions.Default: TPropertyFromAccessorsOptions;
begin
  Result.Prefixes := ['Get', 'Set', 'Is', 'Has'];
  Result.Section := TPropertySectionChoice.Accessor;
  Result.Hiding := TAccessorHiding.Off;
end;

class function TPropertyFromAccessorsOptions.FromNames(const APrefixes: TArray<string>; const ASection,
  AHiding: string): TPropertyFromAccessorsOptions;
begin
  Result := Default;
  Result.Prefixes := APrefixes;
  if SameText(ASection, 'public') then
    Result.Section := TPropertySectionChoice.Public_
  else if SameText(ASection, 'published') then
    Result.Section := TPropertySectionChoice.Published_;
  if SameText(AHiding, 'private') then
    Result.Hiding := TAccessorHiding.Private_
  else if SameText(AHiding, 'protected') then
    Result.Hiding := TAccessorHiding.Protected_;
end;

{ TAccessorMethod }

function TAccessorMethod.Exists: Boolean;
begin
  Result := NamePos.Line >= 0;
end;

{ TAccessorProperty }

function TAccessorProperty.IsIndexed: Boolean;
begin
  Result := IndexCount > 0;
end;

function TAccessorProperty.Declaration: string;
begin
  Result := 'property ' + Name;
  if IsIndexed then
    Result := Result + '[' + IndexParameters + ']';
  Result := Result + ': ' + TypeName;
  if ReadField <> '' then
    Result := Result + ' read ' + ReadField
  else if Getter.Exists then
    Result := Result + ' read ' + Getter.Name;
  if Setter.Exists then
    Result := Result + ' write ' + Setter.Name;
  Result := Result + ';';
end;

function TAccessorProperty.Section(AChoice: TPropertySectionChoice): TMemberSection;
begin
  Result := TMemberSection.Private_;
  if Getter.Exists and (Getter.Section > Result) then
    Result := Getter.Section;
  if Setter.Exists and (Setter.Section > Result) then
    Result := Setter.Section;
  if (AChoice = TPropertySectionChoice.Public_) and (Result < TMemberSection.Public_) then
    Result := TMemberSection.Public_
  else if AChoice = TPropertySectionChoice.Published_ then
    Result := TMemberSection.Published_;
end;

{ Klassen lesen }

type
  /// <summary>Abschnitt einer Klasse: Sichtbarkeitszeile (bzw. Kopfzeile) und Zeilen der Mitglieder.</summary>
  TClassSection = record
    Section: TMemberSection;
    IsStrict: Boolean;
    /// <summary>Zeile des Schlüsselworts; beim ersten Abschnitt ohne Schlüsselwort die Kopfzeile.</summary>
    HeadLine: Integer;
    /// <summary>Letzte Zeile je Mitglied.</summary>
    MemberLines: TArray<Integer>;
  end;

  TRoutineInfo = record
    Node: TSyntaxNode;
    Name: string;
    IsFunction: Boolean;
    IsClassMethod: Boolean;
    ResultType: string;
    /// <summary>Je Parameter "const A: Integer" (Gruppen einzeln) und der Typ allein.</summary>
    ParameterTexts: TArray<string>;
    ParameterTypes: TArray<string>;
    /// <summary>Alle Parameter ohne var/out und ohne Standardwert.</summary>
    PlainParameters: Boolean;
    Section: TMemberSection;
    Virtual_: Boolean;
  end;

  TClassReader = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLines: TArray<string>;
    FOptions: TPropertyFromAccessorsOptions;
    FDecl: TSyntaxNode;
    FClassNode: TSyntaxNode;
    FRoutines: TArray<TRoutineInfo>;
    FMembers: TArray<string>;
    FFields: TDictionary<string, string>;
    FUsedAccessors: TArray<string>;
    function Count(const AName: string): Integer;
    function HasMember(const AName: string): Boolean;
    function Strip(const AName: string; AGetter: Boolean; const AResultType: string; out ABase: string): Boolean;
    function Method(const ARoutine: TRoutineInfo): TAccessorMethod;
    function TrivialGetter(const AGetter, AField: string): Boolean;
    procedure ReadRoutine(ANode: TSyntaxNode; ASection: TMemberSection);
  public
    Sections: TArray<TClassSection>;
    constructor Create(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>; ADecl: TSyntaxNode;
      const AOptions: TPropertyFromAccessorsOptions);
    destructor Destroy; override;
    function Properties: TArray<TAccessorProperty>;
    function ClassNode: TSyntaxNode;
  end;

function SectionOf(const AName: string; out AIsStrict: Boolean): TMemberSection;
begin
  AIsStrict := ContainsText(AName, 'strict');
  if EndsText('private', AName) then
    Result := TMemberSection.Private_
  else if EndsText('protected', AName) then
    Result := TMemberSection.Protected_
  else if EndsText('published', AName) then
    Result := TMemberSection.Published_
  else
    Result := TMemberSection.Public_;
end;

constructor TClassReader.Create(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>;
  ADecl: TSyntaxNode; const AOptions: TPropertyFromAccessorsOptions);
var
  Index: Integer;
  Child, TypeRef: TSyntaxNode;
  Current: TClassSection;
  Section: TMemberSection;
  IsStrict: Boolean;
  Match: TMatch;
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FLines := ALines;
  FDecl := ADecl;
  FOptions := AOptions;
  FClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  FFields := TDictionary<string, string>.Create;
  Current := Default(TClassSection);
  Current.Section := TMemberSection.Public_;
  Current.HeadLine := ADecl.StartPos.Line;
  Section := Current.Section;
  for Index := 0 to FClassNode.ChildCount - 1 do
  begin
    Child := FClassNode[Index];
    case Child.Kind of
      TSyntaxKind.Visibility:
        begin
          Sections := Sections + [Current];
          Current := Default(TClassSection);
          Current.Section := SectionOf(Child.Name, IsStrict);
          Current.IsStrict := IsStrict;
          Current.HeadLine := Child.StartPos.Line;
          Section := Current.Section;
        end;
      TSyntaxKind.Field:
        begin
          Current.MemberLines := Current.MemberLines + [Child.EndPos.Line];
          FMembers := FMembers + [Child.Name];
          TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
          if TypeRef <> nil then
            FFields.AddOrSetValue(UpperCase(Child.Name), Collapse(NodeText(FText, TypeRef)));
        end;
      TSyntaxKind.RoutineHeader:
        begin
          Current.MemberLines := Current.MemberLines + [Child.EndPos.Line];
          FMembers := FMembers + [Child.Name];
          ReadRoutine(Child, Section);
        end;
      TSyntaxKind.PropertyDecl:
        begin
          Current.MemberLines := Current.MemberLines + [Child.EndPos.Line];
          FMembers := FMembers + [Child.Name];
          Match := TRegEx.Match(NodeText(FText, Child), '\b(?:read|write)\s+(\w+)', [roIgnoreCase]);
          while Match.Success do
          begin
            FUsedAccessors := FUsedAccessors + [Match.Groups[1].Value];
            Match := Match.NextMatch;
          end;
        end;
    else
      if Child.Kind <> TSyntaxKind.TypeReference then
        Current.MemberLines := Current.MemberLines + [Child.EndPos.Line];
    end;
  end;
  Sections := Sections + [Current];
end;

destructor TClassReader.Destroy;
begin
  FFields.Free;
  inherited;
end;

function TClassReader.ClassNode: TSyntaxNode;
begin
  Result := FClassNode;
end;

procedure TClassReader.ReadRoutine(ANode: TSyntaxNode; ASection: TMemberSection);
var
  Info: TRoutineInfo;
  Index, Part: Integer;
  Child, Parameters, Parameter, TypeRef: TSyntaxNode;
  Head, Modifier, TypeName: string;
  Names: TArray<string>;
begin
  Info := Default(TRoutineInfo);
  Info.Node := ANode;
  Info.Name := ANode.Name;
  Info.Section := ASection;
  Head := Copy(FText, ANode.StartOffset + 1, 20);
  Info.IsClassMethod := TRegEx.IsMatch(Head, '^class\s', [roIgnoreCase]);
  if Info.IsClassMethod then
    Head := TrimLeft(Copy(Head, 6, MaxInt));
  Info.IsFunction := StartsText('function', Head);
  // Generische Methoden kann eine Property nicht benutzen.
  Info.PlainParameters := ANode.FindChild(TSyntaxKind.GenericParams) = nil;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    if Child.Kind = TSyntaxKind.TypeReference then
      Info.ResultType := Collapse(NodeText(FText, Child))
    else if (Child.Kind = TSyntaxKind.Directive) and (IndexText(Child.Name, VirtualDirectives) >= 0) then
      Info.Virtual_ := True;
  end;
  Parameters := ANode.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
    for Index := 0 to Parameters.ChildCount - 1 do
    begin
      Parameter := Parameters[Index];
      TypeRef := Parameter.FindChild(TSyntaxKind.TypeReference);
      // Ohne Typ (untypisiert) oder mit Standardwert: keine Zugriffsmethode.
      if (TypeRef = nil) or (Parameter.ChildCount > 1) or
        not (Parameter.Modifier in [TParameterModifier.None, TParameterModifier.ConstParam]) then
      begin
        Info.PlainParameters := False;
        Continue;
      end;
      TypeName := Collapse(NodeText(FText, TypeRef));
      Modifier := '';
      if Parameter.Modifier = TParameterModifier.ConstParam then
        Modifier := 'const ';
      Names := Parameter.Name.Split([',']);
      for Part := 0 to High(Names) do
      begin
        Info.ParameterTexts := Info.ParameterTexts + [Modifier + Trim(Names[Part]) + ': ' + TypeName];
        Info.ParameterTypes := Info.ParameterTypes + [TypeName];
      end;
    end;
  FRoutines := FRoutines + [Info];
end;

function TClassReader.Count(const AName: string): Integer;
var
  Routine: TRoutineInfo;
begin
  Result := 0;
  for Routine in FRoutines do
    if SameText(Routine.Name, AName) then
      Inc(Result);
end;

function TClassReader.HasMember(const AName: string): Boolean;
begin
  Result := IndexText(AName, FMembers) >= 0;
end;

function TClassReader.Strip(const AName: string; AGetter: Boolean; const AResultType: string;
  out ABase: string): Boolean;
var
  Prefix: string;
begin
  for Prefix in FOptions.Prefixes do
  begin
    if (Prefix = '') or (Length(AName) <= Length(Prefix)) or not StartsText(Prefix, AName) or
      not CharInSet(AName[Length(Prefix) + 1], ['A'..'Z', '_']) then
      Continue;
    if AGetter then
    begin
      if SameText(Prefix, 'Set') then
        Continue;
      if (SameText(Prefix, 'Is') or SameText(Prefix, 'Has')) and not SameText(AResultType, 'Boolean') then
        Continue;
    end
    else if SameText(Prefix, 'Get') or SameText(Prefix, 'Is') or SameText(Prefix, 'Has') then
      Continue;
    ABase := Copy(AName, Length(Prefix) + 1, MaxInt);
    Exit(True);
  end;
  Result := False;
end;

function TClassReader.Method(const ARoutine: TRoutineInfo): TAccessorMethod;
var
  Token: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Result := Default(TAccessorMethod);
  Result.Name := ARoutine.Name;
  Result.Section := ARoutine.Section;
  Result.Virtual_ := ARoutine.Virtual_;
  Result.NamePos := ARoutine.Node.StartPos;
  Tokens := FTree.Tokens;
  for Token := TSyntaxTree.FirstTokenOf(Tokens, ARoutine.Node.StartOffset) to High(Tokens) do
    if (Tokens[Token].Offset >= ARoutine.Node.StartOffset) and (Tokens[Token].Kind = TPascalTokenKind.Identifier) and
      SameText(Tokens[Token].Text, ARoutine.Name) then
    begin
      Result.NamePos := Tokens[Token].StartPos;
      Break;
    end;
  Result.FirstLine := ARoutine.Node.StartPos.Line;
  while (Result.FirstLine > 0) and StartsText('///', Trim(FLines[Result.FirstLine - 1])) do
    Dec(Result.FirstLine);
  Result.LastLine := ARoutine.Node.EndPos.Line;
end;

function TClassReader.TrivialGetter(const AGetter, AField: string): Boolean;
var
  Qualified: string;
  Found: TSyntaxNode;
begin
  Qualified := FDecl.Name + '.' + AGetter;
  Found := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (Found = nil) and (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(ANode.Name, Qualified) then
        Found := ANode;
      Result := Found = nil;
    end);
  Result := False;
  // Nur Kopf und Rumpf, im Rumpf genau "Result := FX;".
  if (Found = nil) or (Found.ChildCount <> 2) or (Found[1].Kind <> TSyntaxKind.Block) or
    (Found[1].ChildCount <> 1) then
    Exit;
  Found := Found[1][0];
  Result := (Found.Kind = TSyntaxKind.AssignStatement) and SameText(Found.Name, 'Result') and
    (Found.ChildCount = 2) and (Found[1].Kind = TSyntaxKind.Identifier) and SameText(Found[1].Name, AField);
end;

function SameTypes(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if not SameText(A[Index], B[Index]) then
        Exit(False);
end;

function TClassReader.Properties: TArray<TAccessorProperty>;
var
  Order: TList<string>;
  Getters, Setters: TDictionary<string, TRoutineInfo>;
  Routine, Getter, Setter: TRoutineInfo;
  Base, Key, Name, FieldType: string;
  HasGetter, HasSetter: Boolean;
  Item: TAccessorProperty;
  IndexTypes: TArray<string>;
begin
  Result := nil;
  Order := TList<string>.Create;
  Getters := TDictionary<string, TRoutineInfo>.Create;
  Setters := TDictionary<string, TRoutineInfo>.Create;
  try
    for Routine in FRoutines do
    begin
      if Routine.IsClassMethod or not Routine.PlainParameters or (Count(Routine.Name) <> 1) or
        (IndexText(Routine.Name, FUsedAccessors) >= 0) then
        Continue;
      if Routine.IsFunction and (Routine.ResultType <> '') then
      begin
        if not Strip(Routine.Name, True, Routine.ResultType, Base) then
          Continue;
        Key := UpperCase(Base);
        // Bei GetX und IsX gewinnt der Präfix, der zuerst eingestellt ist.
        if Getters.ContainsKey(Key) then
          Continue;
        Getters.Add(Key, Routine);
      end
      else if not Routine.IsFunction and (Length(Routine.ParameterTypes) > 0) then
      begin
        if not Strip(Routine.Name, False, '', Base) then
          Continue;
        Key := UpperCase(Base);
        if Setters.ContainsKey(Key) then
          Continue;
        Setters.Add(Key, Routine);
      end
      else
        Continue;
      if Order.IndexOf(Key) < 0 then
        Order.Add(Key);
    end;
    for Key in Order do
    begin
      HasGetter := Getters.TryGetValue(Key, Getter);
      HasSetter := Setters.TryGetValue(Key, Setter);
      Item := Default(TAccessorProperty);
      Item.ClassName := FDecl.Name;
      Item.ClassLine := FDecl.StartPos.Line;
      Item.Getter.NamePos := TTextPosition.Create(-1, -1);
      Item.Setter.NamePos := TTextPosition.Create(-1, -1);
      if HasGetter and HasSetter then
      begin
        IndexTypes := Copy(Setter.ParameterTypes, 0, Length(Setter.ParameterTypes) - 1);
        // Nicht zusammenpassende Paare: die Property entsteht nur aus dem Getter.
        if not SameText(Getter.ResultType, Setter.ParameterTypes[High(Setter.ParameterTypes)]) or
          not SameTypes(Getter.ParameterTypes, IndexTypes) then
          HasSetter := False;
      end;
      if HasGetter then
      begin
        Strip(Getter.Name, True, Getter.ResultType, Base);
        Item.TypeName := Getter.ResultType;
        Item.IndexParameters := string.Join('; ', Getter.ParameterTexts);
        Item.IndexCount := Length(Getter.ParameterTexts);
        Item.Getter := Method(Getter);
      end
      else
      begin
        Strip(Setter.Name, False, '', Base);
        Item.TypeName := Setter.ParameterTypes[High(Setter.ParameterTypes)];
        Item.IndexParameters := string.Join('; ', Copy(Setter.ParameterTexts, 0, Length(Setter.ParameterTexts) - 1));
        Item.IndexCount := Length(Setter.ParameterTexts) - 1;
      end;
      if HasSetter then
        Item.Setter := Method(Setter);
      Name := Base;
      if Item.IsIndexed and not HasMember(TPropertyFromAccessors.Plural(Base)) then
        Name := TPropertyFromAccessors.Plural(Base);
      if HasMember(Name) then
        Continue;
      Item.Name := Name;
      if HasGetter and not Item.IsIndexed and FFields.TryGetValue(UpperCase('F' + Base), FieldType) and
        SameText(FieldType, Item.TypeName) and TrivialGetter(Getter.Name, 'F' + Base) then
        Item.ReadField := 'F' + Base;
      Result := Result + [Item];
    end;
  finally
    Setters.Free;
    Getters.Free;
    Order.Free;
  end;
end;

/// <summary>Typdeklarationen mit Klasse (auch geschachtelt), in Reihenfolge.</summary>
function ClassDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) and
          (ANode.FindChild(TSyntaxKind.ClassType).EndPos.Line > ANode.StartPos.Line) then
          Found := Found + [ANode];
        Result := True;
      end);
  Result := Found;
end;

{ TPropertyFromAccessors }

class function TPropertyFromAccessors.SectionName(ASection: TMemberSection): string;
begin
  case ASection of
    TMemberSection.Private_:
      Result := 'private';
    TMemberSection.Protected_:
      Result := 'protected';
    TMemberSection.Published_:
      Result := 'published';
  else
    Result := 'public';
  end;
end;

class function TPropertyFromAccessors.Plural(const AName: string): string;
var
  Last: Char;
begin
  Result := AName;
  if AName = '' then
    Exit;
  Last := AName[Length(AName)];
  if CharInSet(Last, ['y', 'Y']) and (Length(AName) > 1) and not CharInSet(AName[Length(AName) - 1],
    ['a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U']) then
    Result := Copy(AName, 1, Length(AName) - 1) + 'ies'
  else if CharInSet(Last, ['s', 'x', 'z', 'S', 'X', 'Z']) or EndsText('ch', AName) or EndsText('sh', AName) then
    Result := AName + 'es'
  else
    Result := AName + 's';
end;

class function TPropertyFromAccessors.Find(ATree: TSyntaxTree; const AText: string;
  const AOptions: TPropertyFromAccessorsOptions): TArray<TAccessorProperty>;
var
  Decl: TSyntaxNode;
  Reader: TClassReader;
  Lines: TArray<string>;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  for Decl in ClassDecls(ATree) do
  begin
    Reader := TClassReader.Create(ATree, AText, Lines, Decl, AOptions);
    try
      Result := Result + Reader.Properties;
    finally
      Reader.Free;
    end;
  end;
end;

class function TPropertyFromAccessors.At(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const AOptions: TPropertyFromAccessorsOptions; out AWholeClass: Boolean): TArray<TAccessorProperty>;
var
  Item: TAccessorProperty;
begin
  Result := nil;
  AWholeClass := False;
  for Item in Find(ATree, AText, AOptions) do
    if Item.ClassLine = ALine then
    begin
      AWholeClass := True;
      Result := Result + [Item];
    end
    else if (Item.Getter.Exists and (ALine >= Item.Getter.NamePos.Line) and (ALine <= Item.Getter.LastLine)) or
      (Item.Setter.Exists and (ALine >= Item.Setter.NamePos.Line) and (ALine <= Item.Setter.LastLine)) then
    begin
      Result := [Item];
      Exit;
    end;
end;

class function TPropertyFromAccessors.CanHide(const AMethod: TAccessorMethod;
  const AOptions: TPropertyFromAccessorsOptions): Boolean;
var
  Target: TMemberSection;
begin
  Result := False;
  if not AMethod.Exists or AMethod.Virtual_ or (AOptions.Hiding = TAccessorHiding.Off) then
    Exit;
  Target := TMemberSection.Private_;
  if AOptions.Hiding = TAccessorHiding.Protected_ then
    Target := TMemberSection.Protected_;
  Result := AMethod.Section > Target;
end;

function Accessors(const AProperty: TAccessorProperty): TArray<TAccessorMethod>;
begin
  Result := nil;
  if AProperty.Getter.Exists then
    Result := Result + [AProperty.Getter];
  if AProperty.Setter.Exists then
    Result := Result + [AProperty.Setter];
end;

type
  TInsertion = record
    Position: TTextPosition;
    Text: string;
  end;

procedure AddInsertion(var AInsertions: TArray<TInsertion>; const APosition: TTextPosition; const AText: string);
var
  Index: Integer;
  Item: TInsertion;
begin
  for Index := 0 to High(AInsertions) do
    if AInsertions[Index].Position = APosition then
    begin
      AInsertions[Index].Text := AInsertions[Index].Text + AText;
      Exit;
    end;
  Item.Position := APosition;
  Item.Text := AText;
  AInsertions := AInsertions + [Item];
end;

class function TPropertyFromAccessors.Edits(ATree: TSyntaxTree; const AText: string;
  const AProperties: TArray<TAccessorProperty>; const AHidden: TArray<string>;
  const AOptions: TPropertyFromAccessorsOptions): TArray<TTextEdit>;
var
  Lines: TArray<string>;
  LB: string;
  Deleted: TDictionary<Integer, Boolean>;
  Insertions: TArray<TInsertion>;
  Opened: TDictionary<Integer, string>;

  function IsDeleted(ALine: Integer): Boolean;
  begin
    Result := Deleted.ContainsKey(ALine);
  end;

  /// <summary>Letzte nicht gelöschte Zeile des Abschnitts; die Kopfzeile, wenn alle wandern.</summary>
  function LastKept(const ASection: TClassSection): Integer;
  var
    Index: Integer;
  begin
    Result := ASection.HeadLine;
    for Index := High(ASection.MemberLines) downto 0 do
      if not IsDeleted(ASection.MemberLines[Index]) then
        Exit(ASection.MemberLines[Index]);
  end;

  function LastLine(const ASection: TClassSection): Integer;
  begin
    Result := ASection.HeadLine;
    if ASection.MemberLines <> nil then
      Result := ASection.MemberLines[High(ASection.MemberLines)];
  end;

  function LineEnd(ALine: Integer): TTextPosition;
  begin
    Result := TTextPosition.Create(ALine, Length(Lines[ALine]));
  end;

var
  Decl: TSyntaxNode;
  Reader: TClassReader;
  Item: TAccessorProperty;
  Methods: TArray<TAccessorMethod>;
  Method: TAccessorMethod;
  Section, Target: TMemberSection;
  ClassIndent, MemberIndent, Moved, Head, Opening_: string;
  Index, Line, Anchor, After, HideIndex: Integer;
  Found: Boolean;
  Insertion: TInsertion;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  LB := TTextLines.LineBreakOf(AText);
  Insertions := nil;
  Opened := TDictionary<Integer, string>.Create;
  Deleted := TDictionary<Integer, Boolean>.Create;
  try
    // Zuerst alle wandernden Methoden: Die Einfügestellen dürfen nicht in gelöschten Zeilen liegen.
    for Item in AProperties do
      for Method in Accessors(Item) do
        if (IndexText(Method.Name, AHidden) >= 0) and CanHide(Method, AOptions) then
          for Line := Method.FirstLine to Method.LastLine do
            Deleted.AddOrSetValue(Line, True);
    for Decl in ClassDecls(ATree) do
    begin
      Reader := TClassReader.Create(ATree, AText, Lines, Decl, AOptions);
      try
        ClassIndent := TTextLines.IndentOf(Lines[Decl.StartPos.Line]);
        MemberIndent := ClassIndent + '  ';
        for Index := 0 to High(Reader.Sections) do
          if Reader.Sections[Index].MemberLines <> nil then
          begin
            MemberIndent := TTextLines.IndentOf(Lines[Reader.Sections[Index].MemberLines[0]]);
            Break;
          end;
        for Item in AProperties do
        begin
          if (Item.ClassLine <> Decl.StartPos.Line) or not SameText(Item.ClassName, Decl.Name) then
            Continue;
          Section := Item.Section(AOptions.Section);
          After := -1;
          if Item.Getter.Exists then
            After := Item.Getter.LastLine;
          if Item.Setter.Exists and (Item.Setter.LastLine > After) then
            After := Item.Setter.LastLine;
          // Einfügestelle: Ende des letzten passenden Abschnitts hinter den Zugriffsmethoden.
          Anchor := -1;
          for Index := High(Reader.Sections) downto 0 do
            if (Reader.Sections[Index].Section = Section) and not Reader.Sections[Index].IsStrict and
              (LastLine(Reader.Sections[Index]) >= After) then
            begin
              Anchor := LastKept(Reader.Sections[Index]);
              Break;
            end;
          // Verborgene Methoden in einen private- bzw. protected-Abschnitt vor der Property.
          Methods := nil;
          for Method in Accessors(Item) do
            if (IndexText(Method.Name, AHidden) >= 0) and CanHide(Method, AOptions) then
              Methods := Methods + [Method];
          Moved := '';
          for Method in Methods do
            for Line := Method.FirstLine to Method.LastLine do
              Moved := Moved + Lines[Line] + LB;
          Head := '';
          if Anchor < 0 then
          begin
            // Neuer Abschnitt vor "end": hinter die letzte bleibende Zeile der Klasse.
            Anchor := Reader.ClassNode.EndPos.Line - 1;
            while (Anchor > Decl.StartPos.Line) and IsDeleted(Anchor) do
              Dec(Anchor);
            Head := ClassIndent + SectionName(Section) + LB;
          end;
          if Moved <> '' then
          begin
            Target := TMemberSection.Private_;
            if AOptions.Hiding = TAccessorHiding.Protected_ then
              Target := TMemberSection.Protected_;
            Found := False;
            for HideIndex := High(Reader.Sections) downto 0 do
              if (Reader.Sections[HideIndex].Section = Target) and not Reader.Sections[HideIndex].IsStrict and
                (LastKept(Reader.Sections[HideIndex]) < Anchor) then
              begin
                AddInsertion(Insertions, LineEnd(LastKept(Reader.Sections[HideIndex])),
                  LB + Copy(Moved, 1, Length(Moved) - Length(LB)));
                Found := True;
                Break;
              end;
            if not Found then
            begin
              // Eigener Abschnitt direkt vor der Property, danach geht ihr Abschnitt weiter.
              Head := ClassIndent + SectionName(Target) + LB + Moved + ClassIndent + SectionName(Section) + LB;
            end;
          end;
          // Mehrere Properties an derselben Stelle: Abschnitt nur öffnen, wenn dort zuletzt ein anderer begann.
          if Opened.TryGetValue(Anchor, Opening_) then
          begin
            if (Head = '') and (Opening_ <> SectionName(Section)) then
              Head := ClassIndent + SectionName(Section) + LB
            else if (Moved = '') and (Opening_ = SectionName(Section)) then
              Head := '';
          end;
          if Head <> '' then
            Opened.AddOrSetValue(Anchor, SectionName(Section));
          AddInsertion(Insertions, LineEnd(Anchor), LB + Head + MemberIndent + Item.Declaration);
        end;
      finally
        Reader.Free;
      end;
    end;
    for Line in Deleted.Keys do
      if not Deleted.ContainsKey(Line - 1) then
      begin
        Index := Line;
        while Deleted.ContainsKey(Index + 1) do
          Inc(Index);
        Result := Result + [TTextEdit.Create(TTextRange.Create(Line, 0, Index + 1, 0), '')];
      end;
    for Insertion in Insertions do
      Result := Result + [TTextEdit.Create(TTextRange.Create(Insertion.Position, Insertion.Position), Insertion.Text)];
  finally
    Deleted.Free;
    Opened.Free;
  end;
end;

class function TPropertyFromAccessors.IsHeaderName(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Boolean;
var
  Before: Integer;
begin
  Before := PreviousToken(ATokens, ChainStart(ATokens, ANameToken));
  Result := IsWordAt(ATokens, Before, ['function', 'procedure', 'constructor', 'destructor']);
end;

class function TPropertyFromAccessors.UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  AIsGetter: Boolean): TAccessorUse;
var
  Start, Before, After, Close, Argument: Integer;
begin
  Start := ChainStart(ATokens, ANameToken);
  Before := PreviousToken(ATokens, Start);
  if IsWordAt(ATokens, Before, ['read', 'write', 'stored', 'inherited', 'function', 'procedure']) then
    Exit(TAccessorUse.Keep);
  if IsSymbolAt(ATokens, Before, '@') or IsSymbolAt(ATokens, Before, '@@') then
    Exit(TAccessorUse.Pointer_);
  After := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  if AIsGetter then
  begin
    if IsSymbolAt(ATokens, After, '(') then
      Exit(TAccessorUse.Call);
    if IsSymbolAt(ATokens, After, ':=') then
      Exit(TAccessorUse.Keep);
    // Als Anweisung (X.GetCaption;) gibt es keine Property-Form.
    if ((Before < 0) or IsWordAt(ATokens, Before, StatementStarts)) and IsWordAt(ATokens, After, StatementEnds) then
      Exit(TAccessorUse.Keep);
    // Zuweisung oder Argument: Methodenzeiger möglich, der Typ des Ziels entscheidet.
    if UnclearTarget(ATokens, ANameToken, Argument) >= 0 then
      Exit(TAccessorUse.Unclear);
    Exit(TAccessorUse.Call);
  end;
  if not IsSymbolAt(ATokens, After, '(') then
    Exit(TAccessorUse.Pointer_);
  Close := Closing(ATokens, After);
  if (Close >= 0) and ((Before < 0) or IsWordAt(ATokens, Before, StatementStarts) or IsSymbolAt(ATokens, Before, ':'))
    and ((NextToken(ATokens, Close) < 0) or IsWordAt(ATokens, NextToken(ATokens, Close), StatementEnds)) then
    Result := TAccessorUse.Call
  else
    Result := TAccessorUse.Keep;
end;

class function TPropertyFromAccessors.UnclearTarget(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  out AArgument: Integer): Integer;
var
  Start, Before, Index, Depth, Callee: Integer;
begin
  AArgument := -1;
  Result := -1;
  Start := ChainStart(ATokens, ANameToken);
  Before := PreviousToken(ATokens, Start);
  // Der Getter muss der ganze Ausdruck sein: nach ihm ";" bzw. "," oder ")".
  Index := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  if IsSymbolAt(ATokens, Before, ':=') then
  begin
    if not ((Index < 0) or IsWordAt(ATokens, Index, StatementEnds)) then
      Exit;
    Result := PreviousToken(ATokens, Before);
    if (Result >= 0) and (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
      Result := -1;
    Exit;
  end;
  if not (IsSymbolAt(ATokens, Before, '(') or IsSymbolAt(ATokens, Before, ',')) or
    not (IsSymbolAt(ATokens, Index, ')') or IsSymbolAt(ATokens, Index, ',')) then
    Exit;
  // Öffnende Klammer des Aufrufs und die Stelle des Arguments suchen.
  Depth := 0;
  Index := Before;
  AArgument := 0;
  while Index >= 0 do
  begin
    if IsSymbolAt(ATokens, Index, ')') or IsSymbolAt(ATokens, Index, ']') then
      Inc(Depth)
    else if IsSymbolAt(ATokens, Index, '(') or IsSymbolAt(ATokens, Index, '[') then
    begin
      if Depth = 0 then
        Break;
      Dec(Depth);
    end
    else if (Depth = 0) and IsSymbolAt(ATokens, Index, ',') then
      Inc(AArgument)
    else if (Depth = 0) and (IsSymbolAt(ATokens, Index, ';') or IsWordAt(ATokens, Index, ['begin', 'then', 'do'])) then
      Break;
    Dec(Index);
  end;
  if not IsSymbolAt(ATokens, Index, '(') then
  begin
    AArgument := -1;
    Exit;
  end;
  Callee := PreviousToken(ATokens, Index);
  if (Callee >= 0) and (ATokens[Callee].Kind = TPascalTokenKind.Identifier) then
    Result := Callee
  else
    AArgument := -1;
end;

class function TPropertyFromAccessors.CallEdit(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  const AProperty: TAccessorProperty; AIsGetter: Boolean; out AEdits: TArray<TTextEdit>): Boolean;
var
  Open, Close, Count, Value: Integer;
  Commas: TArray<Integer>;
  NameStart: TTextPosition;
begin
  AEdits := nil;
  Result := False;
  NameStart := ATokens[ANameToken].StartPos;
  Open := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  Close := -1;
  Count := 0;
  Commas := nil;
  if IsSymbolAt(ATokens, Open, '(') then
  begin
    Close := Closing(ATokens, Open);
    if Close < 0 then
      Exit;
    Commas := TopLevelCommas(ATokens, Open, Close);
    if NextToken(ATokens, Open) <> Close then
      Count := Length(Commas) + 1;
  end;
  if AIsGetter then
  begin
    if Count <> AProperty.IndexCount then
      Exit;
    if Close < 0 then
      AEdits := [TTextEdit.Create(TTextRange.Create(NameStart, ATokens[ANameToken].EndPos), AProperty.Name)]
    else if not AProperty.IsIndexed then
      AEdits := [TTextEdit.Create(TTextRange.Create(NameStart, ATokens[Close].EndPos), AProperty.Name)]
    else
      // GetItem(I) → Items[I]: nur Name und Klammern, das Argument bleibt.
      AEdits := [TTextEdit.Create(TTextRange.Create(NameStart, ATokens[Open].EndPos), AProperty.Name + '['),
        TTextEdit.Create(TTextRange.Create(ATokens[Close].StartPos, ATokens[Close].EndPos), ']')];
    Exit(True);
  end;
  if (Close < 0) or (Count <> AProperty.IndexCount + 1) then
    Exit;
  if AProperty.IsIndexed then
  begin
    // SetItem(I, V) → Items[I] := V
    Value := NextToken(ATokens, Commas[High(Commas)]);
    AEdits := [TTextEdit.Create(TTextRange.Create(NameStart, ATokens[Open].EndPos), AProperty.Name + '['),
      TTextEdit.Create(TTextRange.Create(ATokens[Commas[High(Commas)]].StartPos, ATokens[Value].StartPos), '] := ')];
  end
  else
  begin
    // SetCaption(V) → Caption := V
    Value := NextToken(ATokens, Open);
    AEdits := [TTextEdit.Create(TTextRange.Create(NameStart, ATokens[Value].StartPos), AProperty.Name + ' := ')];
  end;
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ATokens[PreviousToken(ATokens, Close)].EndPos,
    ATokens[Close].EndPos), '')];
  Result := True;
end;

end.
