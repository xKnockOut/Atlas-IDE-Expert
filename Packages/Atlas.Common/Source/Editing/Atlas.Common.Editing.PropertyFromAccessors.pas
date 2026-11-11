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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines;

const
  cVirtualDirectives: array[0..5] of string = ('virtual', 'dynamic', 'override', 'abstract', 'reintroduce', 'message');
  cStatementStarts: array[0..8] of string = (';', 'begin', 'then', 'else', 'do', 'try', 'finally', 'except', 'repeat');
  cStatementEnds: array[0..5] of string = (';', 'end', 'else', 'until', 'except', 'finally');

{ Tokens }

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
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
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if IsSymbolAt(ATokens, Result, '(') or IsSymbolAt(ATokens, Result, '[') then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Öffnende Klammer zu AClose (")" oder "]"); -1 ohne.</summary>
function Opening(const ATokens: TArray<TPascalToken>; AClose: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AClose;
  while Result >= 0 do
  begin
    if IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(ATokens, Result, '(') or IsSymbolAt(ATokens, Result, '[') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
    Dec(Result);
  end;
end;

/// <summary>Hinter einem generischen Namen (Foo&lt;T&gt;) das Token nach "&gt;"; sonst AIndex.</summary>
function SkipGenericArgs(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  if not IsSymbolAt(ATokens, AIndex, '<') then
  begin
    Exit;
  end;
  mDepth := 0;
  while Result <= High(ATokens) do
  begin
    if IsSymbolAt(ATokens, Result, '<') then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(ATokens, Result, '>') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(NextToken(ATokens, Result));
      end;
    end
    else if IsSymbolAt(ATokens, Result, ';') or IsSymbolAt(ATokens, Result, ':=') then
    begin
      Exit(AIndex);
    end;
    Inc(Result);
  end;
  Result := AIndex;
end;

/// <summary>Anfang eines Teils A, B[1] bzw. C(2) einer Kette, der bei APart endet; -1 ohne.</summary>
function PartStart(const ATokens: TArray<TPascalToken>; APart: Integer): Integer;
var
  mBefore: Integer;
begin
  Result := APart;
  while IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') do
  begin
    Result := Opening(ATokens, Result);
    if Result < 0 then
    begin
      Exit;
    end;
    // Name vor der Klammer (Aufruf, Index); ohne Name ist die Klammer der Anfang.
    mBefore := PreviousToken(ATokens, Result);
    if ((mBefore >= 0) and (ATokens[mBefore].Kind = TPascalTokenKind.Identifier)) or
      IsSymbolAt(ATokens, mBefore, ')') or IsSymbolAt(ATokens, mBefore, ']') then
    begin
      Result := mBefore;
    end
    else
    begin
      Break;
    end;
  end;
end;

/// <summary>Erstes Token des Ausdrucks A.B[1].C(2).Name, dessen Name bei ANameToken steht.</summary>
function ChainStart(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Integer;
var
  mDot, mPart: Integer;
begin
  Result := ANameToken;
  mDot := PreviousToken(ATokens, Result);
  while IsSymbolAt(ATokens, mDot, '.') do
  begin
    mPart := PartStart(ATokens, PreviousToken(ATokens, mDot));
    if mPart < 0 then
    begin
      Exit;
    end;
    Result := mPart;
    mDot := PreviousToken(ATokens, Result);
  end;
end;

/// <summary>Kommas der obersten Ebene zwischen AOpen und AClose.</summary>
function TopLevelCommas(const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<Integer>;
var
  mIndex, mDepth: Integer;
begin
  Result := nil;
  mDepth := 0;
  mIndex := NextToken(ATokens, AOpen);
  while (mIndex >= 0) and (mIndex < AClose) do
  begin
    if IsSymbolAt(ATokens, mIndex, '(') or IsSymbolAt(ATokens, mIndex, '[') then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(ATokens, mIndex, ')') or IsSymbolAt(ATokens, mIndex, ']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsSymbolAt(ATokens, mIndex, ',') then
    begin
      Result := Result + [mIndex];
    end;
    mIndex := NextToken(ATokens, mIndex);
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
  begin
    Result.Section := TPropertySectionChoice.Public_;
  end
  else if SameText(ASection, 'published') then
  begin
    Result.Section := TPropertySectionChoice.Published_;
  end;
  if SameText(AHiding, 'private') then
  begin
    Result.Hiding := TAccessorHiding.Private_;
  end
  else if SameText(AHiding, 'protected') then
  begin
    Result.Hiding := TAccessorHiding.Protected_;
  end;
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
  begin
    Result := Result + '[' + IndexParameters + ']';
  end;
  Result := Result + ': ' + TypeName;
  if ReadField <> '' then
  begin
    Result := Result + ' read ' + ReadField;
  end
  else if Getter.Exists then
  begin
    Result := Result + ' read ' + Getter.Name;
  end;
  if Setter.Exists then
  begin
    Result := Result + ' write ' + Setter.Name;
  end;
  Result := Result + ';';
end;

function TAccessorProperty.Section(AChoice: TPropertySectionChoice): TMemberSection;
begin
  Result := TMemberSection.Private_;
  if Getter.Exists and (Getter.Section > Result) then
  begin
    Result := Getter.Section;
  end;
  if Setter.Exists and (Setter.Section > Result) then
  begin
    Result := Setter.Section;
  end;
  if (AChoice = TPropertySectionChoice.Public_) and (Result < TMemberSection.Public_) then
  begin
    Result := TMemberSection.Public_;
  end
  else if AChoice = TPropertySectionChoice.Published_ then
  begin
    Result := TMemberSection.Published_;
  end;
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
    /// <summary>Anzahl der Methoden je Name (Großbuchstaben); ersetzt das Abzählen aller Methoden je Kandidat.
    /// </summary>
    FNameCounts: TDictionary<string, Integer>;
    function Count(const AName: string): Integer;
    function HasMember(const AName: string): Boolean;
    function Strip(const AName: string; AGetter: Boolean; const AResultType: string; out ABase: string): Boolean;
    function Method(const ARoutine: TRoutineInfo): TAccessorMethod;
    function TrivialGetter(const AGetter, AField: string): Boolean;
    procedure ReadMember(AChild: TSyntaxNode; var ASection: TClassSection);
    procedure ReadUsedAccessors(AProperty: TSyntaxNode);
    procedure ReadRoutine(ANode: TSyntaxNode; ASection: TMemberSection);
    /// <summary>Kann ARoutine Zugriffsmethode sein (keine Klassenmethode, nicht überladen, noch unbenutzt)?</summary>
    function IsCandidate(const ARoutine: TRoutineInfo): Boolean;
    /// <summary>ARoutine unter dem Namen ohne Präfix in AMap; False, wenn kein Präfix passt oder der Name schon
    /// vergeben ist (bei GetX und IsX gewinnt der Präfix, der zuerst eingestellt ist).</summary>
    function AddAccessor(AMap: TDictionary<string, TRoutineInfo>; const ARoutine: TRoutineInfo; AGetter: Boolean;
      out AKey: string): Boolean;
    procedure Classify(AGetters, ASetters: TDictionary<string, TRoutineInfo>; AOrder: TList<string>);
    function FillFromGetter(var AItem: TAccessorProperty; const AGetter: TRoutineInfo): string;
    function FillFromSetter(var AItem: TAccessorProperty; const ASetter: TRoutineInfo): string;
    /// <summary>Indizierte Properties in der Mehrzahl, wenn der Name frei ist.</summary>
    function PropertyName(const AItem: TAccessorProperty; const ABase: string): string;
    /// <summary>Feld FX für "read", wenn der Getter es nur liefert und es denselben Typ hat; sonst ''.</summary>
    function ReadFieldOf(const AItem: TAccessorProperty; const AGetter: TRoutineInfo; const ABase: string): string;
    function PropertyFor(const AKey: string; AGetters, ASetters: TDictionary<string, TRoutineInfo>;
      out AItem: TAccessorProperty): Boolean;
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
  begin
    Result := TMemberSection.Private_;
  end
  else if EndsText('protected', AName) then
  begin
    Result := TMemberSection.Protected_;
  end
  else if EndsText('published', AName) then
  begin
    Result := TMemberSection.Published_;
  end
  else
  begin
    Result := TMemberSection.Public_;
  end;
end;

/// <summary>Neuer Abschnitt ab der Sichtbarkeit AVisibility.</summary>
function SectionAt(AVisibility: TSyntaxNode): TClassSection;
var
  mIsStrict: Boolean;
begin
  Result := Default(TClassSection);
  Result.Section := SectionOf(AVisibility.Name, mIsStrict);
  Result.IsStrict := mIsStrict;
  Result.HeadLine := AVisibility.StartPos.Line;
end;

/// <summary>Ergebnistyp und Direktiven aus den Kindern des Kopfs ANode.</summary>
procedure ReadHeadChildren(const AText: string; ANode: TSyntaxNode; var AInfo: TRoutineInfo);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if mChild.Kind = TSyntaxKind.TypeReference then
    begin
      AInfo.ResultType := Collapse(NodeText(AText, mChild));
    end
    else if (mChild.Kind = TSyntaxKind.Directive) and (IndexText(mChild.Name, cVirtualDirectives) >= 0) then
    begin
      AInfo.Virtual_ := True;
    end;
  end;
end;

/// <summary>Parameter(gruppe) AParameter; ohne Typ (untypisiert), mit Standardwert, var oder out: keine
/// Zugriffsmethode.</summary>
procedure ReadParameter(const AText: string; AParameter: TSyntaxNode; var AInfo: TRoutineInfo);
var
  mTypeRef: TSyntaxNode;
  mModifier, mTypeName, mName: string;
begin
  mTypeRef := AParameter.FindChild(TSyntaxKind.TypeReference);
  if (mTypeRef = nil) or (AParameter.ChildCount > 1) or
    not (AParameter.Modifier in [TParameterModifier.None, TParameterModifier.ConstParam]) then
  begin
    AInfo.PlainParameters := False;
    Exit;
  end;
  mTypeName := Collapse(NodeText(AText, mTypeRef));
  mModifier := '';
  if AParameter.Modifier = TParameterModifier.ConstParam then
  begin
    mModifier := 'const ';
  end;
  for mName in AParameter.Name.Split([',']) do
  begin
    AInfo.ParameterTexts := AInfo.ParameterTexts + [mModifier + Trim(mName) + ': ' + mTypeName];
    AInfo.ParameterTypes := AInfo.ParameterTypes + [mTypeName];
  end;
end;

/// <summary>Passt der Präfix APrefix zum Namen AName einer Zugriffsmethode? Is und Has nur für Boolean-Getter,
/// Set nur für Setter, Get nur für Getter.</summary>
function PrefixFits(const APrefix, AName: string; AGetter: Boolean; const AResultType: string): Boolean;
begin
  Result := (APrefix <> '') and (Length(AName) > Length(APrefix)) and StartsText(APrefix, AName) and
    CharInSet(AName[Length(APrefix) + 1], ['A'..'Z', '_']);
  if not Result then
  begin
    Exit;
  end;
  if AGetter then
  begin
    Result := not SameText(APrefix, 'Set') and
      not (MatchText(APrefix, ['Is', 'Has']) and not SameText(AResultType, 'Boolean'));
  end
  else
  begin
    Result := not MatchText(APrefix, ['Get', 'Is', 'Has']);
  end;
end;

constructor TClassReader.Create(ATree: TSyntaxTree; const AText: string; const ALines: TArray<string>;
  ADecl: TSyntaxNode; const AOptions: TPropertyFromAccessorsOptions);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mCurrent: TClassSection;
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
  FLines := ALines;
  FDecl := ADecl;
  FOptions := AOptions;
  FClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
  FFields := TDictionary<string, string>.Create;
  FNameCounts := TDictionary<string, Integer>.Create;
  mCurrent := Default(TClassSection);
  mCurrent.Section := TMemberSection.Public_;
  mCurrent.HeadLine := ADecl.StartPos.Line;
  for mIndex := 0 to FClassNode.ChildCount - 1 do
  begin
    mChild := FClassNode[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      Sections := Sections + [mCurrent];
      mCurrent := SectionAt(mChild);
    end
    else
    begin
      ReadMember(mChild, mCurrent);
    end;
  end;
  Sections := Sections + [mCurrent];
end;

procedure TClassReader.ReadMember(AChild: TSyntaxNode; var ASection: TClassSection);
var
  mTypeRef: TSyntaxNode;
begin
  if AChild.Kind <> TSyntaxKind.TypeReference then
  begin
    ASection.MemberLines := ASection.MemberLines + [AChild.EndPos.Line];
  end;
  if AChild.Kind in [TSyntaxKind.Field, TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl] then
  begin
    FMembers := FMembers + [AChild.Name];
  end;
  if AChild.Kind = TSyntaxKind.Field then
  begin
    mTypeRef := AChild.FindChild(TSyntaxKind.TypeReference);
    if mTypeRef <> nil then
    begin
      FFields.AddOrSetValue(UpperCase(AChild.Name), Collapse(NodeText(FText, mTypeRef)));
    end;
  end
  else if AChild.Kind = TSyntaxKind.RoutineHeader then
  begin
    ReadRoutine(AChild, ASection.Section);
  end
  else if AChild.Kind = TSyntaxKind.PropertyDecl then
  begin
    ReadUsedAccessors(AChild);
  end;
end;

procedure TClassReader.ReadUsedAccessors(AProperty: TSyntaxNode);
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(NodeText(FText, AProperty), '\b(?:read|write)\s+(\w+)', [roIgnoreCase]);
  while mMatch.Success do
  begin
    FUsedAccessors := FUsedAccessors + [mMatch.Groups[1].Value];
    mMatch := mMatch.NextMatch;
  end;
end;

destructor TClassReader.Destroy;
begin
  FNameCounts.Free;
  FFields.Free;
  inherited;
end;

function TClassReader.ClassNode: TSyntaxNode;
begin
  Result := FClassNode;
end;

procedure TClassReader.ReadRoutine(ANode: TSyntaxNode; ASection: TMemberSection);
var
  mInfo: TRoutineInfo;
  mIndex: Integer;
  mParameters: TSyntaxNode;
  mHead: string;
begin
  mInfo := Default(TRoutineInfo);
  mInfo.Node := ANode;
  mInfo.Name := ANode.Name;
  mInfo.Section := ASection;
  mHead := Copy(FText, ANode.StartOffset + 1, 20);
  mInfo.IsClassMethod := TRegEx.IsMatch(mHead, '^class\s', [roIgnoreCase]);
  if mInfo.IsClassMethod then
  begin
    mHead := TrimLeft(Copy(mHead, 6, MaxInt));
  end;
  mInfo.IsFunction := StartsText('function', mHead);
  // Generische Methoden kann eine Property nicht benutzen.
  mInfo.PlainParameters := ANode.FindChild(TSyntaxKind.GenericParams) = nil;
  ReadHeadChildren(FText, ANode, mInfo);
  mParameters := ANode.FindChild(TSyntaxKind.Parameters);
  if mParameters <> nil then
  begin
    for mIndex := 0 to mParameters.ChildCount - 1 do
    begin
      ReadParameter(FText, mParameters[mIndex], mInfo);
    end;
  end;
  FRoutines := FRoutines + [mInfo];
  FNameCounts.AddOrSetValue(UpperCase(mInfo.Name), Count(mInfo.Name) + 1);
end;

function TClassReader.Count(const AName: string): Integer;
begin
  if not FNameCounts.TryGetValue(UpperCase(AName), Result) then
  begin
    Result := 0;
  end;
end;

function TClassReader.HasMember(const AName: string): Boolean;
begin
  Result := IndexText(AName, FMembers) >= 0;
end;

function TClassReader.Strip(const AName: string; AGetter: Boolean; const AResultType: string;
  out ABase: string): Boolean;
var
  mPrefix: string;
begin
  for mPrefix in FOptions.Prefixes do
  begin
    if PrefixFits(mPrefix, AName, AGetter, AResultType) then
    begin
      ABase := Copy(AName, Length(mPrefix) + 1, MaxInt);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TClassReader.Method(const ARoutine: TRoutineInfo): TAccessorMethod;
var
  mToken: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := Default(TAccessorMethod);
  Result.Name := ARoutine.Name;
  Result.Section := ARoutine.Section;
  Result.Virtual_ := ARoutine.Virtual_;
  Result.NamePos := ARoutine.Node.StartPos;
  mTokens := FTree.Tokens;
  for mToken := TSyntaxTree.FirstTokenOf(mTokens, ARoutine.Node.StartOffset) to High(mTokens) do
  begin
    if (mTokens[mToken].Offset >= ARoutine.Node.StartOffset) and
      (mTokens[mToken].Kind = TPascalTokenKind.Identifier) and
      SameText(mTokens[mToken].Text, ARoutine.Name) then
    begin
      Result.NamePos := mTokens[mToken].StartPos;
      Break;
    end;
  end;
  Result.FirstLine := ARoutine.Node.StartPos.Line;
  while (Result.FirstLine > 0) and StartsText('///', Trim(FLines[Result.FirstLine - 1])) do
  begin
    Dec(Result.FirstLine);
  end;
  Result.LastLine := ARoutine.Node.EndPos.Line;
end;

function TClassReader.TrivialGetter(const AGetter, AField: string): Boolean;
var
  mQualified: string;
  mFound: TSyntaxNode;
begin
  mQualified := FDecl.Name + '.' + AGetter;
  mFound := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(ANode.Name, mQualified) then
      begin
        mFound := ANode;
      end;
      Result := mFound = nil;
    end);
  Result := False;
  // Nur Kopf und Rumpf, im Rumpf genau "Result := FX;".
  if (mFound = nil) or (mFound.ChildCount <> 2) or (mFound[1].Kind <> TSyntaxKind.Block) or
    (mFound[1].ChildCount <> 1) then
  begin
    Exit;
  end;
  mFound := mFound[1][0];
  Result := (mFound.Kind = TSyntaxKind.AssignStatement) and SameText(mFound.Name, 'Result') and
    (mFound.ChildCount = 2) and (mFound[1].Kind = TSyntaxKind.Identifier) and SameText(mFound[1].Name, AField);
end;

function SameTypes(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if not SameText(A[mIndex], B[mIndex]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Passen Getter und Setter zusammen (Typ und Indexparameter)?</summary>
function AccessorsMatch(const AGetter, ASetter: TRoutineInfo): Boolean;
var
  mIndexTypes: TArray<string>;
begin
  mIndexTypes := Copy(ASetter.ParameterTypes, 0, Length(ASetter.ParameterTypes) - 1);
  Result := SameText(AGetter.ResultType, ASetter.ParameterTypes[High(ASetter.ParameterTypes)]) and
    SameTypes(AGetter.ParameterTypes, mIndexTypes);
end;

function TClassReader.IsCandidate(const ARoutine: TRoutineInfo): Boolean;
begin
  Result := not ARoutine.IsClassMethod and ARoutine.PlainParameters and (Count(ARoutine.Name) = 1) and
    (IndexText(ARoutine.Name, FUsedAccessors) < 0);
end;

function TClassReader.AddAccessor(AMap: TDictionary<string, TRoutineInfo>; const ARoutine: TRoutineInfo;
  AGetter: Boolean; out AKey: string): Boolean;
var
  mBase: string;
begin
  AKey := '';
  Result := Strip(ARoutine.Name, AGetter, ARoutine.ResultType, mBase);
  if not Result then
  begin
    Exit;
  end;
  AKey := UpperCase(mBase);
  Result := not AMap.ContainsKey(AKey);
  if Result then
  begin
    AMap.Add(AKey, ARoutine);
  end;
end;

procedure TClassReader.Classify(AGetters, ASetters: TDictionary<string, TRoutineInfo>; AOrder: TList<string>);
var
  mRoutine: TRoutineInfo;
  mKey: string;
  mAdded: Boolean;
begin
  for mRoutine in FRoutines do
  begin
    if not IsCandidate(mRoutine) then
    begin
      Continue;
    end;
    if mRoutine.IsFunction and (mRoutine.ResultType <> '') then
    begin
      mAdded := AddAccessor(AGetters, mRoutine, True, mKey);
    end
    else if not mRoutine.IsFunction and (Length(mRoutine.ParameterTypes) > 0) then
    begin
      mAdded := AddAccessor(ASetters, mRoutine, False, mKey);
    end
    else
    begin
      mAdded := False;
    end;
    if mAdded and (AOrder.IndexOf(mKey) < 0) then
    begin
      AOrder.Add(mKey);
    end;
  end;
end;

function TClassReader.FillFromGetter(var AItem: TAccessorProperty; const AGetter: TRoutineInfo): string;
begin
  Strip(AGetter.Name, True, AGetter.ResultType, Result);
  AItem.TypeName := AGetter.ResultType;
  AItem.IndexParameters := string.Join('; ', AGetter.ParameterTexts);
  AItem.IndexCount := Length(AGetter.ParameterTexts);
  AItem.Getter := Method(AGetter);
end;

function TClassReader.FillFromSetter(var AItem: TAccessorProperty; const ASetter: TRoutineInfo): string;
begin
  Strip(ASetter.Name, False, '', Result);
  AItem.TypeName := ASetter.ParameterTypes[High(ASetter.ParameterTypes)];
  AItem.IndexParameters := string.Join('; ', Copy(ASetter.ParameterTexts, 0, Length(ASetter.ParameterTexts) - 1));
  AItem.IndexCount := Length(ASetter.ParameterTexts) - 1;
end;

function TClassReader.PropertyName(const AItem: TAccessorProperty; const ABase: string): string;
begin
  Result := ABase;
  if AItem.IsIndexed and not HasMember(TPropertyFromAccessors.Plural(ABase)) then
  begin
    Result := TPropertyFromAccessors.Plural(ABase);
  end;
end;

function TClassReader.ReadFieldOf(const AItem: TAccessorProperty; const AGetter: TRoutineInfo;
  const ABase: string): string;
var
  mFieldType: string;
begin
  Result := '';
  if AItem.IsIndexed or not FFields.TryGetValue(UpperCase('F' + ABase), mFieldType) then
  begin
    Exit;
  end;
  if SameText(mFieldType, AItem.TypeName) and TrivialGetter(AGetter.Name, 'F' + ABase) then
  begin
    Result := 'F' + ABase;
  end;
end;

function TClassReader.PropertyFor(const AKey: string; AGetters, ASetters: TDictionary<string, TRoutineInfo>;
  out AItem: TAccessorProperty): Boolean;
var
  mGetter, mSetter: TRoutineInfo;
  mHasGetter, mHasSetter: Boolean;
  mBase: string;
begin
  mHasGetter := AGetters.TryGetValue(AKey, mGetter);
  mHasSetter := ASetters.TryGetValue(AKey, mSetter);
  AItem := Default(TAccessorProperty);
  AItem.ClassName := FDecl.Name;
  AItem.ClassLine := FDecl.StartPos.Line;
  AItem.Getter.NamePos := TTextPosition.Create(-1, -1);
  AItem.Setter.NamePos := TTextPosition.Create(-1, -1);
  // Nicht zusammenpassende Paare: die Property entsteht nur aus dem Getter.
  if mHasGetter and mHasSetter and not AccessorsMatch(mGetter, mSetter) then
  begin
    mHasSetter := False;
  end;
  if mHasGetter then
  begin
    mBase := FillFromGetter(AItem, mGetter);
  end
  else
  begin
    mBase := FillFromSetter(AItem, mSetter);
  end;
  if mHasSetter then
  begin
    AItem.Setter := Method(mSetter);
  end;
  AItem.Name := PropertyName(AItem, mBase);
  Result := not HasMember(AItem.Name);
  if Result and mHasGetter then
  begin
    AItem.ReadField := ReadFieldOf(AItem, mGetter, mBase);
  end;
end;

function TClassReader.Properties: TArray<TAccessorProperty>;
var
  mOrder: TList<string>;
  mGetters, mSetters: TDictionary<string, TRoutineInfo>;
  mKey: string;
  mItem: TAccessorProperty;
begin
  Result := nil;
  mOrder := TList<string>.Create;
  mGetters := TDictionary<string, TRoutineInfo>.Create;
  mSetters := TDictionary<string, TRoutineInfo>.Create;
  try
    Classify(mGetters, mSetters, mOrder);
    for mKey in mOrder do
    begin
      if PropertyFor(mKey, mGetters, mSetters, mItem) then
      begin
        Result := Result + [mItem];
      end;
    end;
  finally
    mSetters.Free;
    mGetters.Free;
    mOrder.Free;
  end;
end;

/// <summary>Mehrzeilige Klassendeklaration?</summary>
function IsClassDecl(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) and
    (ANode.FindChild(TSyntaxKind.ClassType).EndPos.Line > ANode.StartPos.Line);
end;

/// <summary>Typdeklarationen mit Klasse (auch geschachtelt), in Reihenfolge.</summary>
function ClassDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if IsClassDecl(ANode) then
        begin
          mFound := mFound + [ANode];
        end;
        Result := True;
      end);
  end;
  Result := mFound;
end;

/// <summary>Klassendeklarationen, die ALine enthalten; steigt nur in Knoten ab, die die Zeile abdecken
/// (große Units: nicht jede Klasse je Cursorbewegung lesen).</summary>
function ClassDeclsAt(ATree: TSyntaxTree; ALine: Integer): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode = ATree.Root) or ((ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine));
        if Result and IsClassDecl(ANode) then
        begin
          mFound := mFound + [ANode];
        end;
      end);
  end;
  Result := mFound;
end;

/// <summary>Property-Kandidaten der Klassen ADecls.</summary>
function PropertiesOf(ATree: TSyntaxTree; const AText: string; const ADecls: TArray<TSyntaxNode>;
  const AOptions: TPropertyFromAccessorsOptions): TArray<TAccessorProperty>;
var
  mDecl: TSyntaxNode;
  mReader: TClassReader;
  mLines: TArray<string>;
begin
  Result := nil;
  if ADecls = nil then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  for mDecl in ADecls do
  begin
    mReader := TClassReader.Create(ATree, AText, mLines, mDecl, AOptions);
    try
      Result := Result + mReader.Properties;
    finally
      mReader.Free;
    end;
  end;
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
  mLast: Char;
begin
  Result := AName;
  if AName = '' then
  begin
    Exit;
  end;
  mLast := AName[Length(AName)];
  if CharInSet(mLast, ['y', 'Y']) and (Length(AName) > 1) and not CharInSet(AName[Length(AName) - 1],
    ['a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U']) then
  begin
    Result := Copy(AName, 1, Length(AName) - 1) + 'ies';
  end
  else if CharInSet(mLast, ['s', 'x', 'z', 'S', 'X', 'Z']) or EndsText('ch', AName) or EndsText('sh', AName) then
  begin
    Result := AName + 'es';
  end
  else
  begin
    Result := AName + 's';
  end;
end;

class function TPropertyFromAccessors.Find(ATree: TSyntaxTree; const AText: string;
  const AOptions: TPropertyFromAccessorsOptions): TArray<TAccessorProperty>;
begin
  Result := PropertiesOf(ATree, AText, ClassDecls(ATree), AOptions);
end;

/// <summary>Steht ALine in der Deklaration von AMethod (ab dem Namen)?</summary>
function CoversLine(const AMethod: TAccessorMethod; ALine: Integer): Boolean;
begin
  Result := AMethod.Exists and (ALine >= AMethod.NamePos.Line) and (ALine <= AMethod.LastLine);
end;

class function TPropertyFromAccessors.At(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const AOptions: TPropertyFromAccessorsOptions; out AWholeClass: Boolean): TArray<TAccessorProperty>;
var
  mItem: TAccessorProperty;
begin
  Result := nil;
  AWholeClass := False;
  // Getter und Setter stehen in der Klassendeklaration: Nur Klassen, die die Zeile enthalten, kommen infrage.
  for mItem in PropertiesOf(ATree, AText, ClassDeclsAt(ATree, ALine), AOptions) do
  begin
    if mItem.ClassLine = ALine then
    begin
      AWholeClass := True;
      Result := Result + [mItem];
    end
    else if CoversLine(mItem.Getter, ALine) or CoversLine(mItem.Setter, ALine) then
    begin
      Result := [mItem];
      Exit;
    end;
  end;
end;

class function TPropertyFromAccessors.CanHide(const AMethod: TAccessorMethod;
  const AOptions: TPropertyFromAccessorsOptions): Boolean;
var
  mTarget: TMemberSection;
begin
  Result := False;
  if not AMethod.Exists or AMethod.Virtual_ or (AOptions.Hiding = TAccessorHiding.Off) then
  begin
    Exit;
  end;
  mTarget := TMemberSection.Private_;
  if AOptions.Hiding = TAccessorHiding.Protected_ then
  begin
    mTarget := TMemberSection.Protected_;
  end;
  Result := AMethod.Section > mTarget;
end;

function Accessors(const AProperty: TAccessorProperty): TArray<TAccessorMethod>;
begin
  Result := nil;
  if AProperty.Getter.Exists then
  begin
    Result := Result + [AProperty.Getter];
  end;
  if AProperty.Setter.Exists then
  begin
    Result := Result + [AProperty.Setter];
  end;
end;

type
  TInsertion = record
    Position: TTextPosition;
    Text: string;
  end;

procedure AddInsertion(var AInsertions: TArray<TInsertion>; const APosition: TTextPosition; const AText: string);
var
  mIndex: Integer;
  mItem: TInsertion;
begin
  for mIndex := 0 to High(AInsertions) do
  begin
    if AInsertions[mIndex].Position = APosition then
    begin
      AInsertions[mIndex].Text := AInsertions[mIndex].Text + AText;
      Exit;
    end;
  end;
  mItem.Position := APosition;
  mItem.Text := AText;
  AInsertions := AInsertions + [mItem];
end;

function LastLineOf(const ASection: TClassSection): Integer;
begin
  Result := ASection.HeadLine;
  if ASection.MemberLines <> nil then
  begin
    Result := ASection.MemberLines[High(ASection.MemberLines)];
  end;
end;

/// <summary>Letzte Zeile der Zugriffsmethoden von AItem; -1 ohne.</summary>
function AccessorsEnd(const AItem: TAccessorProperty): Integer;
begin
  Result := -1;
  if AItem.Getter.Exists then
  begin
    Result := AItem.Getter.LastLine;
  end;
  if AItem.Setter.Exists and (AItem.Setter.LastLine > Result) then
  begin
    Result := AItem.Setter.LastLine;
  end;
end;

/// <summary>Abschnitt, in den verborgene Zugriffsmethoden wandern.</summary>
function HidingSection(const AOptions: TPropertyFromAccessorsOptions): TMemberSection;
begin
  Result := TMemberSection.Private_;
  if AOptions.Hiding = TAccessorHiding.Protected_ then
  begin
    Result := TMemberSection.Protected_;
  end;
end;

type
  /// <summary>Sammelt für TPropertyFromAccessors.Edits gelöschte Zeilen und Einfügungen.</summary>
  TPropertyWriter = record
    Lines: TArray<string>;
    LB: string;
    Options: TPropertyFromAccessorsOptions;
    Hidden: TArray<string>;
    Deleted: TDictionary<Integer, Boolean>;
    /// <summary>Je Einfügezeile der zuletzt dort geöffnete Abschnitt.</summary>
    Opened: TDictionary<Integer, string>;
    Insertions: TArray<TInsertion>;
    Decl: TSyntaxNode;
    Reader: TClassReader;
    ClassIndent: string;
    MemberIndent: string;
    function IsHidden(const AMethod: TAccessorMethod): Boolean;
    function IsDeleted(ALine: Integer): Boolean;
    /// <summary>Zuerst alle wandernden Methoden: Die Einfügestellen dürfen nicht in gelöschten Zeilen liegen.
    /// </summary>
    procedure MarkDeleted(const AProperties: TArray<TAccessorProperty>);
    /// <summary>Letzte nicht gelöschte Zeile des Abschnitts; die Kopfzeile, wenn alle wandern.</summary>
    function LastKept(const ASection: TClassSection): Integer;
    function LineEnd(ALine: Integer): TTextPosition;
    function Heading(ASection: TMemberSection): string;
    procedure SetIndents;
    procedure AddClass(ADecl: TSyntaxNode; AReader: TClassReader; const AProperties: TArray<TAccessorProperty>);
    /// <summary>Einfügestelle: Ende des letzten passenden Abschnitts hinter den Zugriffsmethoden; -1 ohne.</summary>
    function AnchorOf(const AItem: TAccessorProperty; ASection: TMemberSection): Integer;
    /// <summary>Neuer Abschnitt vor "end": hinter die letzte bleibende Zeile der Klasse.</summary>
    function NewSectionAnchor: Integer;
    function MovedText(const AItem: TAccessorProperty): string;
    /// <summary>Verborgene Methoden in einen private- bzw. protected-Abschnitt vor der Property.</summary>
    procedure HideMoved(const AMoved: string; AAnchor: Integer; ASection: TMemberSection; var AHead: string);
    /// <summary>Mehrere Properties an derselben Stelle: Abschnitt nur öffnen, wenn dort zuletzt ein anderer
    /// begann.</summary>
    procedure ResolveHead(AAnchor: Integer; ASection: TMemberSection; const AMoved: string; var AHead: string);
    procedure AddProperty(const AItem: TAccessorProperty);
    function DeletionEdits: TArray<TTextEdit>;
    function InsertionEdits: TArray<TTextEdit>;
  end;

function TPropertyWriter.IsHidden(const AMethod: TAccessorMethod): Boolean;
begin
  Result := (IndexText(AMethod.Name, Hidden) >= 0) and TPropertyFromAccessors.CanHide(AMethod, Options);
end;

function TPropertyWriter.IsDeleted(ALine: Integer): Boolean;
begin
  Result := Deleted.ContainsKey(ALine);
end;

procedure TPropertyWriter.MarkDeleted(const AProperties: TArray<TAccessorProperty>);
var
  mItem: TAccessorProperty;
  mMethod: TAccessorMethod;
  mLine: Integer;
begin
  for mItem in AProperties do
  begin
    for mMethod in Accessors(mItem) do
    begin
      if IsHidden(mMethod) then
      begin
        for mLine := mMethod.FirstLine to mMethod.LastLine do
        begin
          Deleted.AddOrSetValue(mLine, True);
        end;
      end;
    end;
  end;
end;

function TPropertyWriter.LastKept(const ASection: TClassSection): Integer;
var
  mIndex: Integer;
begin
  Result := ASection.HeadLine;
  for mIndex := High(ASection.MemberLines) downto 0 do
  begin
    if not IsDeleted(ASection.MemberLines[mIndex]) then
    begin
      Exit(ASection.MemberLines[mIndex]);
    end;
  end;
end;

function TPropertyWriter.LineEnd(ALine: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, Length(Lines[ALine]));
end;

function TPropertyWriter.Heading(ASection: TMemberSection): string;
begin
  Result := ClassIndent + TPropertyFromAccessors.SectionName(ASection) + LB;
end;

procedure TPropertyWriter.SetIndents;
var
  mIndex: Integer;
begin
  ClassIndent := TTextLines.IndentOf(Lines[Decl.StartPos.Line]);
  MemberIndent := ClassIndent + '  ';
  for mIndex := 0 to High(Reader.Sections) do
  begin
    if Reader.Sections[mIndex].MemberLines <> nil then
    begin
      MemberIndent := TTextLines.IndentOf(Lines[Reader.Sections[mIndex].MemberLines[0]]);
      Exit;
    end;
  end;
end;

procedure TPropertyWriter.AddClass(ADecl: TSyntaxNode; AReader: TClassReader;
  const AProperties: TArray<TAccessorProperty>);
var
  mItem: TAccessorProperty;
begin
  Decl := ADecl;
  Reader := AReader;
  SetIndents;
  for mItem in AProperties do
  begin
    if (mItem.ClassLine = Decl.StartPos.Line) and SameText(mItem.ClassName, Decl.Name) then
    begin
      AddProperty(mItem);
    end;
  end;
end;

function TPropertyWriter.AnchorOf(const AItem: TAccessorProperty; ASection: TMemberSection): Integer;
var
  mAfter, mIndex: Integer;
  mSection: TClassSection;
begin
  mAfter := AccessorsEnd(AItem);
  for mIndex := High(Reader.Sections) downto 0 do
  begin
    mSection := Reader.Sections[mIndex];
    if (mSection.Section = ASection) and not mSection.IsStrict and (LastLineOf(mSection) >= mAfter) then
    begin
      Exit(LastKept(mSection));
    end;
  end;
  Result := -1;
end;

function TPropertyWriter.NewSectionAnchor: Integer;
begin
  Result := Reader.ClassNode.EndPos.Line - 1;
  while (Result > Decl.StartPos.Line) and IsDeleted(Result) do
  begin
    Dec(Result);
  end;
end;

function TPropertyWriter.MovedText(const AItem: TAccessorProperty): string;
var
  mMethod: TAccessorMethod;
  mLine: Integer;
begin
  Result := '';
  for mMethod in Accessors(AItem) do
  begin
    if IsHidden(mMethod) then
    begin
      for mLine := mMethod.FirstLine to mMethod.LastLine do
      begin
        Result := Result + Lines[mLine] + LB;
      end;
    end;
  end;
end;

procedure TPropertyWriter.HideMoved(const AMoved: string; AAnchor: Integer; ASection: TMemberSection;
  var AHead: string);
var
  mTarget: TMemberSection;
  mIndex: Integer;
  mSection: TClassSection;
begin
  mTarget := HidingSection(Options);
  for mIndex := High(Reader.Sections) downto 0 do
  begin
    mSection := Reader.Sections[mIndex];
    if (mSection.Section = mTarget) and not mSection.IsStrict and (LastKept(mSection) < AAnchor) then
    begin
      AddInsertion(Insertions, LineEnd(LastKept(mSection)), LB + Copy(AMoved, 1, Length(AMoved) - Length(LB)));
      Exit;
    end;
  end;
  // Eigener Abschnitt direkt vor der Property, danach geht ihr Abschnitt weiter.
  AHead := Heading(mTarget) + AMoved + Heading(ASection);
end;

procedure TPropertyWriter.ResolveHead(AAnchor: Integer; ASection: TMemberSection; const AMoved: string;
  var AHead: string);
var
  mName, mOpening: string;
begin
  mName := TPropertyFromAccessors.SectionName(ASection);
  if Opened.TryGetValue(AAnchor, mOpening) then
  begin
    if (AHead = '') and (mOpening <> mName) then
    begin
      AHead := Heading(ASection);
    end
    else if (AMoved = '') and (mOpening = mName) then
    begin
      AHead := '';
    end;
  end;
  if AHead <> '' then
  begin
    Opened.AddOrSetValue(AAnchor, mName);
  end;
end;

procedure TPropertyWriter.AddProperty(const AItem: TAccessorProperty);
var
  mSection: TMemberSection;
  mAnchor: Integer;
  mMoved, mHead: string;
begin
  mSection := AItem.Section(Options.Section);
  mAnchor := AnchorOf(AItem, mSection);
  mMoved := MovedText(AItem);
  mHead := '';
  if mAnchor < 0 then
  begin
    mAnchor := NewSectionAnchor;
    mHead := Heading(mSection);
  end;
  if mMoved <> '' then
  begin
    HideMoved(mMoved, mAnchor, mSection, mHead);
  end;
  ResolveHead(mAnchor, mSection, mMoved, mHead);
  AddInsertion(Insertions, LineEnd(mAnchor), LB + mHead + MemberIndent + AItem.Declaration);
end;

function TPropertyWriter.DeletionEdits: TArray<TTextEdit>;
var
  mLine, mLast: Integer;
begin
  Result := nil;
  for mLine in Deleted.Keys do
  begin
    if Deleted.ContainsKey(mLine - 1) then
    begin
      Continue;
    end;
    mLast := mLine;
    while Deleted.ContainsKey(mLast + 1) do
    begin
      Inc(mLast);
    end;
    Result := Result + [TTextEdit.Create(TTextRange.Create(mLine, 0, mLast + 1, 0), '')];
  end;
end;

function TPropertyWriter.InsertionEdits: TArray<TTextEdit>;
var
  mInsertion: TInsertion;
begin
  Result := nil;
  for mInsertion in Insertions do
  begin
    Result := Result + [TTextEdit.Create(TTextRange.Create(mInsertion.Position, mInsertion.Position),
      mInsertion.Text)];
  end;
end;

class function TPropertyFromAccessors.Edits(ATree: TSyntaxTree; const AText: string;
  const AProperties: TArray<TAccessorProperty>; const AHidden: TArray<string>;
  const AOptions: TPropertyFromAccessorsOptions): TArray<TTextEdit>;
var
  mWriter: TPropertyWriter;
  mDecl: TSyntaxNode;
  mReader: TClassReader;
begin
  mWriter := Default(TPropertyWriter);
  mWriter.Lines := TTextLines.SplitLines(AText);
  mWriter.LB := TTextLines.LineBreakOf(AText);
  mWriter.Options := AOptions;
  mWriter.Hidden := AHidden;
  mWriter.Opened := TDictionary<Integer, string>.Create;
  mWriter.Deleted := TDictionary<Integer, Boolean>.Create;
  try
    mWriter.MarkDeleted(AProperties);
    for mDecl in ClassDecls(ATree) do
    begin
      mReader := TClassReader.Create(ATree, AText, mWriter.Lines, mDecl, AOptions);
      try
        mWriter.AddClass(mDecl, mReader, AProperties);
      finally
        mReader.Free;
      end;
    end;
    Result := mWriter.DeletionEdits + mWriter.InsertionEdits;
  finally
    mWriter.Deleted.Free;
    mWriter.Opened.Free;
  end;
end;

class function TPropertyFromAccessors.IsHeaderName(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Boolean;
var
  mBefore: Integer;
begin
  mBefore := PreviousToken(ATokens, ChainStart(ATokens, ANameToken));
  Result := IsWordAt(ATokens, mBefore, ['function', 'procedure', 'constructor', 'destructor']);
end;

/// <summary>Beginnt hinter ABefore eine Anweisung (bzw. steht dort ":" eines case-Zweigs)?</summary>
function StartsStatement(const ATokens: TArray<TPascalToken>; ABefore: Integer): Boolean;
begin
  Result := (ABefore < 0) or IsWordAt(ATokens, ABefore, cStatementStarts) or IsSymbolAt(ATokens, ABefore, ':');
end;

/// <summary>Endet vor AIndex eine Anweisung?</summary>
function EndsStatement(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex < 0) or IsWordAt(ATokens, AIndex, cStatementEnds);
end;

function GetterUse(const ATokens: TArray<TPascalToken>; ANameToken, ABefore: Integer): TAccessorUse;
var
  mAfter, mArgument: Integer;
begin
  mAfter := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  if IsSymbolAt(ATokens, mAfter, '(') then
  begin
    Result := TAccessorUse.Call;
  end
  else if IsSymbolAt(ATokens, mAfter, ':=') then
  begin
    Result := TAccessorUse.Keep;
  end
  // Als Anweisung (X.GetCaption;) gibt es keine Property-Form.
  else if ((ABefore < 0) or IsWordAt(ATokens, ABefore, cStatementStarts)) and
    IsWordAt(ATokens, mAfter, cStatementEnds) then
  begin
    Result := TAccessorUse.Keep;
  end
  // Zuweisung oder Argument: Methodenzeiger möglich, der Typ des Ziels entscheidet.
  else if TPropertyFromAccessors.UnclearTarget(ATokens, ANameToken, mArgument) >= 0 then
  begin
    Result := TAccessorUse.Unclear;
  end
  else
  begin
    Result := TAccessorUse.Call;
  end;
end;

function SetterUse(const ATokens: TArray<TPascalToken>; ANameToken, ABefore: Integer): TAccessorUse;
var
  mAfter, mClose: Integer;
begin
  mAfter := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  if not IsSymbolAt(ATokens, mAfter, '(') then
  begin
    Exit(TAccessorUse.Pointer_);
  end;
  mClose := Closing(ATokens, mAfter);
  Result := TAccessorUse.Keep;
  if (mClose >= 0) and StartsStatement(ATokens, ABefore) and EndsStatement(ATokens, NextToken(ATokens, mClose)) then
  begin
    Result := TAccessorUse.Call;
  end;
end;

/// <summary>Ziel der Zuweisung, deren Wert der Getter ist (AAfter: Token hinter ihm); -1 ohne.</summary>
function AssignTarget(const ATokens: TArray<TPascalToken>; AAssign, AAfter: Integer): Integer;
begin
  Result := -1;
  if not EndsStatement(ATokens, AAfter) then
  begin
    Exit;
  end;
  Result := PreviousToken(ATokens, AAssign);
  if (Result >= 0) and (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
  begin
    Result := -1;
  end;
end;

/// <summary>Öffnende Klammer des Aufrufs vor AFrom; AArgument zählt die Kommas davor (Stelle ab 0).</summary>
function ArgumentOpen(const ATokens: TArray<TPascalToken>; AFrom: Integer; out AArgument: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  AArgument := 0;
  Result := AFrom;
  while Result >= 0 do
  begin
    if IsSymbolAt(ATokens, Result, ')') or IsSymbolAt(ATokens, Result, ']') then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(ATokens, Result, '(') or IsSymbolAt(ATokens, Result, '[') then
    begin
      if mDepth = 0 then
      begin
        Exit;
      end;
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsSymbolAt(ATokens, Result, ',') then
    begin
      Inc(AArgument);
    end
    else if (mDepth = 0) and (IsSymbolAt(ATokens, Result, ';') or
      IsWordAt(ATokens, Result, ['begin', 'then', 'do'])) then
    begin
      Exit;
    end;
    Dec(Result);
  end;
end;

/// <summary>Name des Aufrufs, dessen Argument bei ABefore beginnt; -1 ohne (AArgument dann -1).</summary>
function ArgumentCall(const ATokens: TArray<TPascalToken>; ABefore: Integer; out AArgument: Integer): Integer;
var
  mOpen, mCallee: Integer;
begin
  Result := -1;
  mOpen := ArgumentOpen(ATokens, ABefore, AArgument);
  if IsSymbolAt(ATokens, mOpen, '(') then
  begin
    mCallee := PreviousToken(ATokens, mOpen);
    if (mCallee >= 0) and (ATokens[mCallee].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := mCallee;
    end;
  end;
  if Result < 0 then
  begin
    AArgument := -1;
  end;
end;

type
  /// <summary>Klammern und Argumente eines Aufrufs der Zugriffsmethode.</summary>
  TCallShape = record
    NameToken: Integer;
    /// <summary>Token hinter dem Namen ("(" bei Argumenten).</summary>
    Open: Integer;
    /// <summary>Schließende Klammer; -1 ohne Klammern.</summary>
    Close: Integer;
    Count: Integer;
    Commas: TArray<Integer>;
  end;

/// <summary>Aufruf bei ANameToken lesen; False bei einer Klammer ohne Gegenstück.</summary>
function ReadCall(const ATokens: TArray<TPascalToken>; ANameToken: Integer; out ACall: TCallShape): Boolean;
begin
  ACall := Default(TCallShape);
  ACall.NameToken := ANameToken;
  ACall.Open := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  ACall.Close := -1;
  Result := True;
  if not IsSymbolAt(ATokens, ACall.Open, '(') then
  begin
    Exit;
  end;
  ACall.Close := Closing(ATokens, ACall.Open);
  Result := ACall.Close >= 0;
  if Result then
  begin
    ACall.Commas := TopLevelCommas(ATokens, ACall.Open, ACall.Close);
    if NextToken(ATokens, ACall.Open) <> ACall.Close then
    begin
      ACall.Count := Length(ACall.Commas) + 1;
    end;
  end;
end;

function GetterEdits(const ATokens: TArray<TPascalToken>; const ACall: TCallShape;
  const AProperty: TAccessorProperty; out AEdits: TArray<TTextEdit>): Boolean;
var
  mNameStart: TTextPosition;
begin
  AEdits := nil;
  Result := ACall.Count = AProperty.IndexCount;
  if not Result then
  begin
    Exit;
  end;
  mNameStart := ATokens[ACall.NameToken].StartPos;
  if ACall.Close < 0 then
  begin
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNameStart, ATokens[ACall.NameToken].EndPos),
      AProperty.Name)];
  end
  else if not AProperty.IsIndexed then
  begin
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNameStart, ATokens[ACall.Close].EndPos), AProperty.Name)];
  end
  else
  begin
    // GetItem(I) → Items[I]: nur Name und Klammern, das Argument bleibt.
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNameStart, ATokens[ACall.Open].EndPos),
      AProperty.Name + '['), TTextEdit.Create(TTextRange.Create(ATokens[ACall.Close].StartPos,
      ATokens[ACall.Close].EndPos), ']')];
  end;
end;

function SetterEdits(const ATokens: TArray<TPascalToken>; const ACall: TCallShape;
  const AProperty: TAccessorProperty; out AEdits: TArray<TTextEdit>): Boolean;
var
  mNameStart: TTextPosition;
  mValue, mComma: Integer;
begin
  AEdits := nil;
  Result := (ACall.Close >= 0) and (ACall.Count = AProperty.IndexCount + 1);
  if not Result then
  begin
    Exit;
  end;
  mNameStart := ATokens[ACall.NameToken].StartPos;
  if AProperty.IsIndexed then
  begin
    // SetItem(I, V) → Items[I] := V
    mComma := ACall.Commas[High(ACall.Commas)];
    mValue := NextToken(ATokens, mComma);
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNameStart, ATokens[ACall.Open].EndPos),
      AProperty.Name + '['), TTextEdit.Create(TTextRange.Create(ATokens[mComma].StartPos,
      ATokens[mValue].StartPos), '] := ')];
  end
  else
  begin
    // SetCaption(V) → Caption := V
    mValue := NextToken(ATokens, ACall.Open);
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mNameStart, ATokens[mValue].StartPos),
      AProperty.Name + ' := ')];
  end;
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ATokens[PreviousToken(ATokens, ACall.Close)].EndPos,
    ATokens[ACall.Close].EndPos), '')];
end;

class function TPropertyFromAccessors.UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  AIsGetter: Boolean): TAccessorUse;
var
  mBefore: Integer;
begin
  mBefore := PreviousToken(ATokens, ChainStart(ATokens, ANameToken));
  if IsWordAt(ATokens, mBefore, ['read', 'write', 'stored', 'inherited', 'function', 'procedure']) then
  begin
    Result := TAccessorUse.Keep;
  end
  else if IsSymbolAt(ATokens, mBefore, '@') or IsSymbolAt(ATokens, mBefore, '@@') then
  begin
    Result := TAccessorUse.Pointer_;
  end
  else if AIsGetter then
  begin
    Result := GetterUse(ATokens, ANameToken, mBefore);
  end
  else
  begin
    Result := SetterUse(ATokens, ANameToken, mBefore);
  end;
end;

class function TPropertyFromAccessors.UnclearTarget(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  out AArgument: Integer): Integer;
var
  mBefore, mAfter: Integer;
begin
  AArgument := -1;
  Result := -1;
  mBefore := PreviousToken(ATokens, ChainStart(ATokens, ANameToken));
  // Der Getter muss der ganze Ausdruck sein: nach ihm ";" bzw. "," oder ")".
  mAfter := SkipGenericArgs(ATokens, NextToken(ATokens, ANameToken));
  if IsSymbolAt(ATokens, mBefore, ':=') then
  begin
    Result := AssignTarget(ATokens, mBefore, mAfter);
  end
  else if (IsSymbolAt(ATokens, mBefore, '(') or IsSymbolAt(ATokens, mBefore, ',')) and
    (IsSymbolAt(ATokens, mAfter, ')') or IsSymbolAt(ATokens, mAfter, ',')) then
  begin
    // Öffnende Klammer des Aufrufs und die Stelle des Arguments suchen.
    Result := ArgumentCall(ATokens, mBefore, AArgument);
  end;
end;

class function TPropertyFromAccessors.CallEdit(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  const AProperty: TAccessorProperty; AIsGetter: Boolean; out AEdits: TArray<TTextEdit>): Boolean;
var
  mCall: TCallShape;
begin
  AEdits := nil;
  Result := ReadCall(ATokens, ANameToken, mCall);
  if Result and AIsGetter then
  begin
    Result := GetterEdits(ATokens, mCall, AProperty, AEdits);
  end
  else if Result then
  begin
    Result := SetterEdits(ATokens, mCall, AProperty, AEdits);
  end;
end;

end.
