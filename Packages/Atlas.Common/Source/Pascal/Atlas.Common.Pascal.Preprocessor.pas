unit Atlas.Common.Pascal.Preprocessor;

// Präprozessor für Object Pascal: bedingte Kompilierung und Include-Dateien.
//
// - Arbeitet auf den Token des Lexers. Ergebnis sind die aktiven Token in
//   Reihenfolge; Token aus Include-Dateien behalten ihre Positionen in ihrer
//   eigenen Datei, FileIndexes sagt, aus welcher Datei jedes Token stammt.
// - Unterstützt $IFDEF, $IFNDEF, $IF, $ELSEIF, $ELSE, $ENDIF, $IFEND, $IFOPT,
//   $DEFINE, $UNDEF und $I/$INCLUDE. $I+ und $I- sind Schalter, keine Includes.
// - $IF-Ausdrücke: Defined, Declared, CompilerVersion, RTLVersion, die
//   booleschen Versionskonstanten RTLVersion111 … aus der Compilerversion,
//   SizeOf/High/Low der Grundtypen aus der Zielplattform, Ord, Zahlen,
//   Konstanten aus den Optionen, Vergleiche, and/or/xor/not, Klammern.
// - Unbekannte Werte (#847): Konstanten aus dem Code, Declared ohne Treffer,
//   unbekannte Typen ergeben „unbekannt“. Ein solcher Zweig gilt als aktiv,
//   ein {$ELSE} dazu ebenfalls; einen Befund gibt es dafür nicht.
// - $IFOPT (#847): Schalterstände aus Einträgen "$R+" usw. in Defines (aus der
//   .dproj, ProjectSwitches), dann lokale {$R-}, {$R-,Q+}, {$RANGECHECKS ON}
//   ab ihrer Position; {$PUSHOPT}/{$POPOPT} sichern und stellen sie wieder her.
//   Unbekannte Schalter ergeben „unbekannt“. Einträge mit "$" sind keine Symbole.
// - Declared fragt Options.Declared, sonst den Index über SetDeclaredProvider.
// - Jede ausgewertete $IF-, $ELSEIF- und $IFOPT-Direktive steht mit Wert und
//   Teilwerten in Checks, für den Hover (#847).
// - Bricht nie ab; Fehler (fehlendes $ENDIF, unbekannte Include-Datei,
//   kaputter Ausdruck) landen in Issues.
// - Inaktive Bereiche werden für das Abblenden im Editor (#23) gesammelt.
// - Wirksame $DEFINE/$UNDEF stehen mit Stelle in DefineSites, für Zustand und
//   Herkunft eines Symbols im Hover (#102).
// - Alle übrigen wirksamen Direktiven ({$R-}, {$WARN …}, {$PUSHOPT} …) stehen
//   mit Stelle in DirectiveSites, für die Compiler-Schalter an einer Stelle
//   (#558).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Sucht eine Include-Datei; AFromFile ist die einbindende Datei ('' = Hauptdatei).</summary>
  TIncludeResolver = reference to function(const AName, AFromFile: string;
    out AFileName, AText: string): Boolean;

  /// <summary>Beantwortet Declared(X); True = deklariert, False = nicht gefunden (gilt als unbekannt).</summary>
  TDeclaredFunc = reference to function(const AName: string): Boolean;

  /// <summary>Wert einer Bedingung (#847). Unknown: ein Wert ist dem Server nicht bekannt; der Zweig gilt als
  /// aktiv, ein {$ELSE} dazu ebenfalls.</summary>
  TConditionValue = (No, Yes, Unknown);

  /// <summary>Teilwert einer Bedingung für den Hover (#847).</summary>
  TConditionPart = record
    /// <summary>Teilausdruck, z. B. "SizeOf(Pointer)", "RTLVersion111" oder bei $IFOPT "R+".</summary>
    Text: string;
    /// <summary>Wert als Text: "8", "wahr", "falsch", "unbekannt".</summary>
    Value: string;
    /// <summary>Herkunft, z. B. "Zielplattform Win64", "Delphi 13", "Index", "DCC_RangeChecking" oder
    /// "{$R-} in Zeile 4"; '' ohne.</summary>
    Origin: string;
  end;

  /// <summary>Ausgewertete $IF-, $ELSEIF- oder $IFOPT-Direktive (#847).</summary>
  TConditionCheck = record
    FileIndex: Integer;
    /// <summary>Bereich der Direktive.</summary>
    Range: TTextRange;
    /// <summary>IF, ELSEIF oder IFOPT.</summary>
    Directive: string;
    Expression: string;
    Value: TConditionValue;
    Parts: TArray<TConditionPart>;
  end;

  TPreprocessorOptions = record
    Defines: TArray<string>;
    CompilerVersion: Double;
    RTLVersion: Double;
    /// <summary>Weitere Konstanten für $IF als Name=Wert.</summary>
    Constants: TArray<TPair<string, Double>>;
    FileName: string;
    ResolveInclude: TIncludeResolver;
    Declared: TDeclaredFunc;
    MaxIncludeDepth: Integer;
    class function Default: TPreprocessorOptions; static;
  end;

  /// <summary>Art eines Präprozessor-Befunds; Include-Probleme werden in Diagnosen unterschieden (#264).</summary>
  TPreprocessorIssueKind = (General, IncludeMissing, IncludeCycle);

  TPreprocessorIssue = record
    Kind: TPreprocessorIssueKind;
    FileIndex: Integer;
    Range: TTextRange;
    /// <summary>Bereich der $I-Direktive in der Hauptdatei, über die der Befund erreicht wurde;
    /// bei FileIndex = 0 gleich Range.</summary>
    RootRange: TTextRange;
    Message: string;
  end;

  TInactiveRange = record
    FileIndex: Integer;
    Range: TTextRange;
  end;

  /// <summary>Zweig eines $IFDEF/$IF (#476): Bereich, Bedingung als Text ("WIN64", "not MSWINDOWS",
  /// bei Verschachtelung "DEBUG und WIN64") und ob er unter den aktuellen Symbolen gilt.</summary>
  TConditionalRange = record
    FileIndex: Integer;
    Range: TTextRange;
    Condition: string;
    Active: Boolean;
  end;

  /// <summary>Wirksames $DEFINE bzw. $UNDEF (#102), in Reihenfolge der Verarbeitung. RootPos ist die Stelle in der
  /// Hauptdatei: die Direktive selbst oder die $I-Direktive, über die die Include-Datei eingebunden ist.</summary>
  TDefineSite = record
    FileIndex: Integer;
    Range: TTextRange;
    RootPos: TTextPosition;
    Name: string;
    Undefine: Boolean;
  end;

  /// <summary>Wirksame Direktive außer Bedingungen, $DEFINE, $UNDEF und $I (#558), in Reihenfolge der
  /// Verarbeitung; RootPos wie bei TDefineSite. Body: Inhalt ohne "{$" und "}".</summary>
  TDirectiveSite = record
    FileIndex: Integer;
    Range: TTextRange;
    RootPos: TTextPosition;
    Body: string;
  end;

  TPreprocessorResult = record
    /// <summary>Aktive Token ohne die verarbeiteten Direktiven.</summary>
    Tokens: TArray<TPascalToken>;
    /// <summary>Je Token der Index in Files.</summary>
    FileIndexes: TArray<Integer>;
    /// <summary>Files[0] ist die Hauptdatei, danach die Include-Dateien.</summary>
    Files: TArray<string>;
    InactiveRanges: TArray<TInactiveRange>;
    /// <summary>Alle Zweige mit Bedingung, deren übergeordneter Zweig gilt (#476).</summary>
    Conditionals: TArray<TConditionalRange>;
    Issues: TArray<TPreprocessorIssue>;
    /// <summary>Symbole am Ende der Datei (nach $DEFINE/$UNDEF).</summary>
    Defines: TArray<string>;
    /// <summary>Wirksame $DEFINE und $UNDEF, auch aus Include-Dateien (#102).</summary>
    DefineSites: TArray<TDefineSite>;
    /// <summary>Ausgewertete Bedingungen unter geltendem Elternzweig (#847).</summary>
    Checks: TArray<TConditionCheck>;
    /// <summary>Übrige wirksame Direktiven, auch aus Include-Dateien (#558).</summary>
    DirectiveSites: TArray<TDirectiveSite>;
  end;

  TPascalPreprocessor = record
  public
    class function Process(const AText: string; const AOptions: TPreprocessorOptions): TPreprocessorResult; static;
    /// <summary>Vordefinierte Symbole für Plattform und Compilerversion (z. B. Win64, 37.0).</summary>
    class function PredefinedSymbols(const APlatform: string; ACompilerVersion: Double): TArray<string>; static;
    /// <summary>Compilerversion zur BDS-Version der Registry: bis Delphi 12 (BDS 23.0) BDS + 13,
    /// z. B. 23.0 -> 36.0; ab Delphi 13 gleich (37.0). 0 für unbekannte Werte.</summary>
    class function CompilerVersionOfBds(ABdsVersion: Double): Double; static;
    /// <summary>Compilerversion aus einem Symbol VERnnn in ADefines (VER360 -> 36.0); 0 ohne.</summary>
    class function CompilerVersionFromDefines(const ADefines: TArray<string>): Double; static;
    /// <summary>Optionen für Editor-Baum und Syntaxfehler (#845): ADefines des Projekts samt Compilerversion
    /// aus VERnnn; leer = Vordefinitionen von Delphi 13 für Win32.</summary>
    class function EditorOptions(const ADefines: TArray<string>): TPreprocessorOptions; overload; static;
    /// <summary>Wie oben, mit Dateiname und Include-Resolver (#860): $DEFINE aus {$I datei.inc} wirken dann
    /// auf die Zweige der Datei.</summary>
    class function EditorOptions(const ADefines: TArray<string>; const AFileName: string;
      const AResolver: TIncludeResolver): TPreprocessorOptions; overload; static;
    /// <summary>Inaktive Bereiche der Hauptdatei (ohne Include-Dateien).</summary>
    class function MainInactive(const AResult: TPreprocessorResult): TArray<TTextRange>; static;
    /// <summary>Zweige der Hauptdatei (ohne Include-Dateien).</summary>
    class function MainConditionals(const AResult: TPreprocessorResult): TArray<TConditionalRange>; static;
    /// <summary>Kann AText bedingte Zweige enthalten ($IF, $IFDEF, $IFNDEF, $IFOPT)?</summary>
    class function HasConditionals(const AText: string): Boolean; static;
    /// <summary>Kann AText {$I datei} oder {$INCLUDE datei} enthalten (#860)? Schalter wie {$I+} zählen nicht.
    /// </summary>
    class function HasIncludes(const AText: string): Boolean; static;
    /// <summary>Wertet einen $IF-Ausdruck aus; unbekannt gilt als True (aktiv), False und AError bei Fehlern.
    /// </summary>
    class function Evaluate(const AExpression: string; const AOptions: TPreprocessorOptions;
      const ADefines: TArray<string>; out AError: string): Boolean; static;
    /// <summary>Wie Evaluate, mit drei Werten und den Teilwerten für den Hover (#847).</summary>
    class function Explain(const AExpression: string; const AOptions: TPreprocessorOptions;
      const ADefines: TArray<string>; out AParts: TArray<TConditionPart>; out AError: string): TConditionValue;
      static;
    /// <summary>Schalterstände für $IFOPT aus den Eigenschaften der .dproj (DCC_RangeChecking → "$R+" usw.,
    /// #847); ohne Eintrag die Vorgabe des Compilers mit "*" ("$R-*"). Die Einträge gehören zu den Defines.</summary>
    class function ProjectSwitches(const AProperties: TArray<TPair<string, string>>): TArray<string>; static;
    /// <summary>Ist ADefine ein Schaltereintrag wie "$R+" statt eines Symbols?</summary>
    class function IsSwitchEntry(const ADefine: string): Boolean; static;
    /// <summary>Eigenschaft der .dproj zum Schalter ALetter ("DCC_RangeChecking" für R); '' ohne.</summary>
    class function SwitchProperty(ALetter: Char): string; static;
    /// <summary>Buchstabe zum langen Schalternamen ("RANGECHECKS" → R, #558); False für andere Namen.</summary>
    class function LongSwitchLetter(const AName: string; out ALetter: Char): Boolean; static;
    /// <summary>Stand des Schalters ALetter ohne Eintrag in der .dproj ('+', '-'); #0, wenn Atlas ihn nicht
    /// kennt (#558).</summary>
    class function SwitchDefault(ALetter: Char): Char; static;
    /// <summary>Declared(X) ohne Options.Declared: fragt AProvider (Server: den Symbolindex); nil = keiner.
    /// </summary>
    class procedure SetDeclaredProvider(const AProvider: TDeclaredFunc); static;
    /// <summary>"Delphi 13" zu CompilerVersion 37 usw.; sonst "CompilerVersion n".</summary>
    class function ProductName(ACompilerVersion: Double): string; static;
    /// <summary>Name aus "{$I Name}", "{$INCLUDE 'Name'}" bzw. "(*$I Name*)"; False bei Schaltern wie {$I+}.
    /// </summary>
    class function IncludeFileOf(const ADirective: string; out AName: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.SyncObjs,
  Atlas.Text.Defines,
  Atlas.Common.Pascal.Lexer;

type
  EPreprocessorExpression = class(Exception);

  /// <summary>Wert im Auswerter: Zahl oder unbekannt (#847).</summary>
  TEvalValue = record
    Known: Boolean;
    Number: Double;
    class function Make(ANumber: Double): TEvalValue; static;
    class function Unknown: TEvalValue; static;
    function IsTrue: Boolean;
    function IsFalse: Boolean;
  end;

  /// <summary>Stand eines Schalters für $IFOPT; fehlt ein Buchstabe, ist er unbekannt.</summary>
  TSwitchState = record
    On_: Boolean;
    /// <summary>"DCC_RangeChecking" oder "{$R-} in Zeile 4".</summary>
    Origin: string;
  end;

  TSwitchTable = TDictionary<Char, TSwitchState>;

  TBranchState = record
    ParentActive: Boolean;
    Taken: Boolean;
    Active: Boolean;
    InElse: Boolean;
    /// <summary>Bedingung des übergeordneten Zweigs, des $IF und des laufenden Zweigs (#476).</summary>
    Outer: string;
    IfText: string;
    Text: string;
    Start: TTextPosition;
  end;

  /// <summary>Rekursiv absteigender Auswerter für $IF-Ausdrücke.</summary>
  TExpressionEvaluator = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FOptions: TPreprocessorOptions;
    FDefines: TDictionary<string, Boolean>;
    FParts: TList<TConditionPart>;
    FPointerSize: Integer;
    FPlatform: string;
    function Peek: TPascalToken;
    function AtEnd: Boolean;
    function Next: TPascalToken;
    procedure Expect(const ASymbol: string);
    function IsWord(const AWord: string): Boolean;
    function ParseOr: TEvalValue;
    function ParseAnd: TEvalValue;
    function ParseComparison: TEvalValue;
    function ParseAdditive: TEvalValue;
    function ParseMultiplicative: TEvalValue;
    function ParseUnary: TEvalValue;
    function ParsePrimary: TEvalValue;
    function ParseFunction(const AName: string; out AValue: TEvalValue): Boolean;
    function ReadName: string;
    procedure AddPart(const AText, AValue, AOrigin: string);
    function BoolText(const AValue: TEvalValue): string;
    function NumberText(const AValue: TEvalValue): string;
    /// <summary>"Delphi 13" für die Herkunft von CompilerVersion und RTLVersion111 …; '' ohne Version.</summary>
    function ProductOrigin: string;
    function Declared(const AName: string; out AOrigin: string): TEvalValue;
    function VersionConstant(const AName: string; out AValue: TEvalValue): Boolean;
    function TypeSize(const AType: string; out AOrigin: string): Integer;
    function TypeRange(const AType: string; out ALow, AHigh: Double; out AOrigin: string): Boolean;
  public
    constructor Create(const AOptions: TPreprocessorOptions; ADefines: TDictionary<string, Boolean>);
    destructor Destroy; override;
    function Evaluate(const AExpression: string): TConditionValue;
    function Parts: TArray<TConditionPart>;
  end;

  TPreprocessorRun = class
  private
    FOptions: TPreprocessorOptions;
    FDefines: TDictionary<string, Boolean>;
    FTokens: TList<TPascalToken>;
    FFileIndexes: TList<Integer>;
    FFiles: TList<string>;
    FInactive: TList<TInactiveRange>;
    FConditionals: TList<TConditionalRange>;
    FIssues: TList<TPreprocessorIssue>;
    FDefineSites: TList<TDefineSite>;
    FDirectiveSites: TList<TDirectiveSite>;
    FChecks: TList<TConditionCheck>;
    FSwitches: TSwitchTable;
    FSwitchStack: TObjectStack<TSwitchTable>;
    FIncludeStack: TList<string>;
    // $I-Direktive der Hauptdatei, die gerade verarbeitet wird.
    FRootRange: TTextRange;
    procedure AddDefineSite(AFileIndex: Integer; const AToken: TPascalToken; const AName: string;
      AUndefine: Boolean);
    procedure AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string;
      AKind: TPreprocessorIssueKind = TPreprocessorIssueKind.General);
    procedure AddDirectiveSite(AFileIndex: Integer; const AToken: TPascalToken);
    procedure ProcessText(const AText: string; AFileIndex, ADepth: Integer);
    procedure Include(const AName: string; AFileIndex, ADepth: Integer; const AToken: TPascalToken);
    function EvaluateCondition(const AExpression, ADirective: string; AFileIndex: Integer;
      const AToken: TPascalToken): TConditionValue;
    function EvaluateSwitch(const AArgument: string; AFileIndex: Integer; const AToken: TPascalToken): TConditionValue;
    function ApplySwitches(const ABody: string; AFileIndex: Integer; const AToken: TPascalToken): Boolean;
    procedure AddCheck(AFileIndex: Integer; const AToken: TPascalToken; const ADirective, AExpression: string;
      AValue: TConditionValue; const AParts: TArray<TConditionPart>);
  public
    constructor Create(const AOptions: TPreprocessorOptions);
    destructor Destroy; override;
    function Run(const AText: string): TPreprocessorResult;
  end;

const
  BooleanValue: array[Boolean] of Double = (0, 1);
  /// <summary>Herkunft eines Schalters ohne Eintrag in der .dproj.</summary>
  DefaultSuffix = '(Vorgabe des Compilers)';

type
  /// <summary>Schalter mit langem Namen ({$RANGECHECKS ON}) und Eigenschaft der .dproj.</summary>
  TSwitchName = record
    Letter: Char;
    Long: string;
    Prop: string;
    /// <summary>Stand ohne Eintrag in der .dproj ('+', '-'; '' = keine Eigenschaft).</summary>
    Default: string;
  end;

const
  SwitchNames: array[0..17] of TSwitchName = (
    (Letter: 'A'; Long: 'ALIGN'; Prop: ''; Default: ''),
    (Letter: 'B'; Long: 'BOOLEVAL'; Prop: ''; Default: ''),
    (Letter: 'C'; Long: 'ASSERTIONS'; Prop: 'DCC_AssertionsAtRuntime'; Default: '+'),
    (Letter: 'D'; Long: 'DEBUGINFO'; Prop: 'DCC_DebugInformation'; Default: '+'),
    (Letter: 'G'; Long: 'IMPORTEDDATA'; Prop: ''; Default: ''),
    (Letter: 'H'; Long: 'LONGSTRINGS'; Prop: ''; Default: ''),
    (Letter: 'I'; Long: 'IOCHECKS'; Prop: 'DCC_IOChecking'; Default: '+'),
    (Letter: 'J'; Long: 'WRITEABLECONST'; Prop: 'DCC_WriteableConstants'; Default: '-'),
    (Letter: 'L'; Long: 'LOCALSYMBOLS'; Prop: 'DCC_LocalDebugSymbols'; Default: '+'),
    (Letter: 'M'; Long: 'TYPEINFO'; Prop: ''; Default: ''),
    (Letter: 'O'; Long: 'OPTIMIZATION'; Prop: 'DCC_Optimize'; Default: '+'),
    (Letter: 'P'; Long: 'OPENSTRINGS'; Prop: ''; Default: ''),
    (Letter: 'Q'; Long: 'OVERFLOWCHECKS'; Prop: 'DCC_IntegerOverflowCheck'; Default: '-'),
    (Letter: 'R'; Long: 'RANGECHECKS'; Prop: 'DCC_RangeChecking'; Default: '-'),
    (Letter: 'T'; Long: 'TYPEDADDRESS'; Prop: ''; Default: ''),
    (Letter: 'U'; Long: 'SAFEDIVIDE'; Prop: ''; Default: ''),
    (Letter: 'V'; Long: 'VARSTRINGCHECKS'; Prop: ''; Default: ''),
    (Letter: 'W'; Long: 'STACKFRAMES'; Prop: 'DCC_GenerateStackFrames'; Default: '-'));

var
  ProviderLock: TCriticalSection;
  DeclaredProvider: TDeclaredFunc;

/// <summary>"R+" bzw. "r-" → Buchstabe und Stand; sonst False.</summary>
function ParseSwitch(const AText: string; out ALetter: Char; out AOn: Boolean): Boolean;
var
  Text: string;
begin
  Text := Trim(AText);
  Result := (Length(Text) = 2) and CharInSet(UpCase(Text[1]), ['A'..'Z']) and CharInSet(Text[2], ['+', '-']);
  if not Result then
    Exit;
  ALetter := UpCase(Text[1]);
  AOn := Text[2] = '+';
end;

function CopySwitches(ASource: TSwitchTable): TSwitchTable;
var
  Letter: Char;
begin
  Result := TSwitchTable.Create;
  for Letter in ASource.Keys do
    Result.Add(Letter, ASource[Letter]);
end;

function ConditionOf(AValue: Boolean): TConditionValue;
begin
  if AValue then
    Result := TConditionValue.Yes
  else
    Result := TConditionValue.No;
end;

function CurrentDeclaredProvider: TDeclaredFunc;
begin
  ProviderLock.Enter;
  try
    Result := DeclaredProvider;
  finally
    ProviderLock.Leave;
  end;
end;

{ TEvalValue }

class function TEvalValue.Make(ANumber: Double): TEvalValue;
begin
  Result.Known := True;
  Result.Number := ANumber;
end;

class function TEvalValue.Unknown: TEvalValue;
begin
  Result.Known := False;
  Result.Number := 0;
end;

function TEvalValue.IsTrue: Boolean;
begin
  Result := Known and (Number <> 0);
end;

function TEvalValue.IsFalse: Boolean;
begin
  Result := Known and (Number = 0);
end;

function DirectiveBody(const AText: string): string;
begin
  // '{$IFDEF X}' bzw. '(*$IFDEF X*)' → 'IFDEF X'
  if (Length(AText) >= 2) and (AText[1] = '{') then
  begin
    Result := Copy(AText, 3, MaxInt);
    if (Result <> '') and (Result[Length(Result)] = '}') then
      Delete(Result, Length(Result), 1);
  end
  else
  begin
    Result := Copy(AText, 4, MaxInt);
    if (Length(Result) >= 2) and (Copy(Result, Length(Result) - 1, 2) = '*)') then
      Delete(Result, Length(Result) - 1, 2);
  end;
  Result := Trim(Result);
end;

procedure SplitDirective(const ABody: string; out AName, AArgument: string);
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(ABody)) and CharInSet(ABody[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(I);
  AName := UpperCase(Copy(ABody, 1, I - 1));
  AArgument := Trim(Copy(ABody, I, MaxInt));
end;

function FirstWord(const AArgument: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(AArgument)) and CharInSet(AArgument[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
    Inc(I);
  Result := Copy(AArgument, 1, I - 1);
end;

function IncludeName(const AArgument: string): string;
var
  Stop: Integer;
begin
  Result := Trim(AArgument);
  if (Result <> '') and (Result[1] = '''') then
  begin
    Stop := Pos('''', Copy(Result, 2, MaxInt));
    if Stop > 0 then
      Result := Copy(Result, 2, Stop - 1)
    else
      Result := Copy(Result, 2, MaxInt);
  end
  else
  begin
    Stop := Pos(' ', Result);
    if Stop > 0 then
      Result := Copy(Result, 1, Stop - 1);
  end;
end;

function IsSwitch(const AArgument: string): Boolean;
begin
  // {$I+} / {$I-}: E/A-Prüfung, kein Include.
  Result := (AArgument = '+') or (AArgument = '-') or
    ((Length(AArgument) >= 1) and CharInSet(AArgument[1], ['+', '-']) and
     ((Length(AArgument) = 1) or (AArgument[2] = ',') or (AArgument[2] = ' ')));
end;

{ TPreprocessorOptions }

class function TPreprocessorOptions.Default: TPreprocessorOptions;
begin
  Result.Defines := nil;
  Result.CompilerVersion := 0;
  Result.RTLVersion := 0;
  Result.Constants := nil;
  Result.FileName := '';
  Result.ResolveInclude := nil;
  Result.Declared := nil;
  Result.MaxIncludeDepth := 16;
end;

{ TExpressionEvaluator }

constructor TExpressionEvaluator.Create(const AOptions: TPreprocessorOptions; ADefines: TDictionary<string, Boolean>);
begin
  inherited Create;
  FOptions := AOptions;
  FDefines := ADefines;
  FParts := TList<TConditionPart>.Create;
  // Zeigergröße und Plattform aus den vordefinierten Symbolen (SizeOf, High, Low).
  if FDefines.ContainsKey('CPU64BITS') or FDefines.ContainsKey('WIN64') then
    FPointerSize := 8
  else if FDefines.ContainsKey('CPU32BITS') or FDefines.ContainsKey('WIN32') then
    FPointerSize := 4
  else
    FPointerSize := 0;
  if FDefines.ContainsKey('WIN64') then
    FPlatform := 'Win64'
  else if FDefines.ContainsKey('WIN32') then
    FPlatform := 'Win32'
  else if FDefines.ContainsKey('LINUX64') then
    FPlatform := 'Linux64'
  else if FDefines.ContainsKey('MACOS64') and FDefines.ContainsKey('CPUARM64') then
    FPlatform := 'OSXARM64'
  else if FDefines.ContainsKey('MACOS64') and not FDefines.ContainsKey('IOS') then
    FPlatform := 'OSX64'
  else if FDefines.ContainsKey('IOS64') then
    FPlatform := 'iOSDevice64'
  else if FDefines.ContainsKey('ANDROID64') then
    FPlatform := 'Android64'
  else if FDefines.ContainsKey('ANDROID') then
    FPlatform := 'Android'
  else
    FPlatform := '';
end;

destructor TExpressionEvaluator.Destroy;
begin
  FParts.Free;
  inherited Destroy;
end;

function TExpressionEvaluator.Parts: TArray<TConditionPart>;
begin
  Result := FParts.ToArray;
end;

procedure TExpressionEvaluator.AddPart(const AText, AValue, AOrigin: string);
var
  Part: TConditionPart;
begin
  Part.Text := AText;
  Part.Value := AValue;
  Part.Origin := AOrigin;
  FParts.Add(Part);
end;

function TExpressionEvaluator.BoolText(const AValue: TEvalValue): string;
begin
  if not AValue.Known then
    Result := 'unbekannt'
  else if AValue.Number <> 0 then
    Result := 'wahr'
  else
    Result := 'falsch';
end;

function TExpressionEvaluator.ProductOrigin: string;
begin
  Result := '';
  if FOptions.CompilerVersion > 0 then
    Result := TPascalPreprocessor.ProductName(FOptions.CompilerVersion);
end;

function TExpressionEvaluator.NumberText(const AValue: TEvalValue): string;
begin
  if AValue.Known then
    Result := FloatToStr(AValue.Number, TFormatSettings.Invariant)
  else
    Result := 'unbekannt';
end;

function TExpressionEvaluator.AtEnd: Boolean;
begin
  Result := FIndex >= Length(FTokens);
end;

function TExpressionEvaluator.Peek: TPascalToken;
begin
  if AtEnd then
  begin
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
  end
  else
    Result := FTokens[FIndex];
end;

function TExpressionEvaluator.Next: TPascalToken;
begin
  if AtEnd then
    raise EPreprocessorExpression.Create('Ausdruck endet unerwartet');
  Result := FTokens[FIndex];
  Inc(FIndex);
end;

procedure TExpressionEvaluator.Expect(const ASymbol: string);
begin
  if AtEnd or not Peek.IsSymbol(ASymbol) then
    raise EPreprocessorExpression.CreateFmt('"%s" erwartet', [ASymbol]);
  Inc(FIndex);
end;

function TExpressionEvaluator.IsWord(const AWord: string): Boolean;
begin
  Result := not AtEnd and (Peek.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
    SameText(Peek.Text, AWord);
end;

function TExpressionEvaluator.ReadName: string;
begin
  if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    raise EPreprocessorExpression.Create('Name erwartet');
  Result := Next.Text;
  // Qualifizierte Namen wie System.SysUtils
  while not AtEnd and Peek.IsSymbol('.') do
  begin
    Inc(FIndex);
    if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
      raise EPreprocessorExpression.Create('Name erwartet');
    Result := Result + '.' + Next.Text;
  end;
end;

function TExpressionEvaluator.Evaluate(const AExpression: string): TConditionValue;
var
  Significant: TList<TPascalToken>;
  Token: TPascalToken;
  Value: TEvalValue;
begin
  Significant := TList<TPascalToken>.Create;
  try
    for Token in TPascalLexer.Tokenize(AExpression) do
      if Token.Kind <> TPascalTokenKind.Comment then
        Significant.Add(Token);
    FTokens := Significant.ToArray;
  finally
    Significant.Free;
  end;
  FIndex := 0;
  FParts.Clear;
  if AtEnd then
    raise EPreprocessorExpression.Create('Ausdruck fehlt');
  Value := ParseOr;
  if not AtEnd then
    raise EPreprocessorExpression.CreateFmt('Unerwartet: "%s"', [Peek.Text]);
  if not Value.Known then
    Result := TConditionValue.Unknown
  else if Value.Number <> 0 then
    Result := TConditionValue.Yes
  else
    Result := TConditionValue.No;
end;

function TExpressionEvaluator.ParseOr: TEvalValue;
var
  Right: TEvalValue;
  IsXor: Boolean;
begin
  Result := ParseAnd;
  while IsWord('or') or IsWord('xor') do
  begin
    IsXor := IsWord('xor');
    Inc(FIndex);
    Right := ParseAnd;
    if IsXor then
    begin
      if Result.Known and Right.Known then
        Result := TEvalValue.Make(BooleanValue[(Result.Number <> 0) xor (Right.Number <> 0)])
      else
        Result := TEvalValue.Unknown;
    end
    // Ein sicher wahrer Teil macht or wahr, auch neben einem unbekannten.
    else if Result.IsTrue or Right.IsTrue then
      Result := TEvalValue.Make(1)
    else if Result.Known and Right.Known then
      Result := TEvalValue.Make(0)
    else
      Result := TEvalValue.Unknown;
  end;
end;

function TExpressionEvaluator.ParseAnd: TEvalValue;
var
  Right: TEvalValue;
begin
  Result := ParseComparison;
  while IsWord('and') do
  begin
    Inc(FIndex);
    Right := ParseComparison;
    if Result.IsFalse or Right.IsFalse then
      Result := TEvalValue.Make(0)
    else if Result.Known and Right.Known then
      Result := TEvalValue.Make(1)
    else
      Result := TEvalValue.Unknown;
  end;
end;

function TExpressionEvaluator.ParseComparison: TEvalValue;
var
  Op: string;
  Right: TEvalValue;
  Value: Boolean;
begin
  Result := ParseAdditive;
  if not AtEnd and (Peek.Kind = TPascalTokenKind.Symbol) then
  begin
    Op := Peek.Text;
    if (Op = '=') or (Op = '<>') or (Op = '<') or (Op = '>') or (Op = '<=') or (Op = '>=') then
    begin
      Inc(FIndex);
      Right := ParseAdditive;
      if not Result.Known or not Right.Known then
        Exit(TEvalValue.Unknown);
      if Op = '=' then
        Value := Result.Number = Right.Number
      else if Op = '<>' then
        Value := Result.Number <> Right.Number
      else if Op = '<' then
        Value := Result.Number < Right.Number
      else if Op = '>' then
        Value := Result.Number > Right.Number
      else if Op = '<=' then
        Value := Result.Number <= Right.Number
      else
        Value := Result.Number >= Right.Number;
      Result := TEvalValue.Make(BooleanValue[Value]);
    end;
  end;
end;

function TExpressionEvaluator.ParseAdditive: TEvalValue;
var
  Plus: Boolean;
  Right: TEvalValue;
begin
  Result := ParseMultiplicative;
  while not AtEnd and (Peek.IsSymbol('+') or Peek.IsSymbol('-')) do
  begin
    Plus := Next.Text = '+';
    Right := ParseMultiplicative;
    if not Result.Known or not Right.Known then
      Result := TEvalValue.Unknown
    else if Plus then
      Result := TEvalValue.Make(Result.Number + Right.Number)
    else
      Result := TEvalValue.Make(Result.Number - Right.Number);
  end;
end;

function TExpressionEvaluator.ParseMultiplicative: TEvalValue;
var
  Op: string;
  Right: TEvalValue;
begin
  Result := ParseUnary;
  while not AtEnd and (Peek.IsSymbol('*') or IsWord('div') or IsWord('mod')) do
  begin
    Op := LowerCase(Next.Text);
    Right := ParseUnary;
    if (Op <> '*') and Right.IsFalse then
      raise EPreprocessorExpression.Create('Division durch null');
    if not Result.Known or not Right.Known then
      Result := TEvalValue.Unknown
    else if Op = '*' then
      Result := TEvalValue.Make(Result.Number * Right.Number)
    else if Op = 'div' then
      Result := TEvalValue.Make(Trunc(Result.Number) div Trunc(Right.Number))
    else
      Result := TEvalValue.Make(Trunc(Result.Number) mod Trunc(Right.Number));
  end;
end;

function TExpressionEvaluator.ParseUnary: TEvalValue;
begin
  if IsWord('not') then
  begin
    Inc(FIndex);
    Result := ParseUnary;
    if Result.Known then
      Result := TEvalValue.Make(BooleanValue[Result.Number = 0]);
  end
  else if not AtEnd and Peek.IsSymbol('-') then
  begin
    Inc(FIndex);
    Result := ParseUnary;
    if Result.Known then
      Result := TEvalValue.Make(-Result.Number);
  end
  else
    Result := ParsePrimary;
end;

function TExpressionEvaluator.Declared(const AName: string; out AOrigin: string): TEvalValue;
var
  Pair: TPair<string, Double>;
  Provider: TDeclaredFunc;
  Constant: TEvalValue;
begin
  AOrigin := '';
  // Was der Präprozessor selbst kennt: System-Konstanten und die Konstanten aus den Optionen.
  if SameText(AName, 'CompilerVersion') or SameText(AName, 'RTLVersion') then
  begin
    AOrigin := 'System';
    Exit(TEvalValue.Make(1));
  end;
  if VersionConstant(AName, Constant) then
  begin
    AOrigin := ProductOrigin;
    if Constant.Known then
      Result := TEvalValue.Make(BooleanValue[Constant.Number <> 0])
    else
      Result := TEvalValue.Unknown;
    Exit;
  end;
  for Pair in FOptions.Constants do
    if SameText(Pair.Key, AName) then
      Exit(TEvalValue.Make(1));
  // Sonst der Index; ohne Treffer bleibt es unbekannt (die Unit kann noch fehlen).
  Provider := FOptions.Declared;
  if not Assigned(Provider) then
    Provider := CurrentDeclaredProvider();
  if Assigned(Provider) and Provider(AName) then
  begin
    AOrigin := 'Index';
    Exit(TEvalValue.Make(1));
  end;
  Result := TEvalValue.Unknown;
end;

function TExpressionEvaluator.VersionConstant(const AName: string; out AValue: TEvalValue): Boolean;
var
  Digits: string;
  Number, Major, Minor: Integer;
  Version: Double;
begin
  // RTLVersion111 (Delphi 11.1) … RTLVersion123: True ab dieser Version. Für die laufende Hauptversion gilt das
  // jüngste Update als installiert.
  Result := False;
  AValue := TEvalValue.Unknown;
  if (Length(AName) <> Length('RTLVersion') + 3) or
    not SameText(Copy(AName, 1, Length('RTLVersion')), 'RTLVersion') then
    Exit;
  Digits := Copy(AName, Length('RTLVersion') + 1, 3);
  if not TryStrToInt(Digits, Number) then
    Exit;
  Major := Number div 10;
  Minor := Number mod 10;
  if (Major < 11) or (Minor = 0) then
    Exit;
  Result := True;
  if FOptions.CompilerVersion <= 0 then
    Exit;
  Version := Major + 24;
  AValue := TEvalValue.Make(BooleanValue[FOptions.CompilerVersion >= Version]);
end;

function TExpressionEvaluator.TypeSize(const AType: string; out AOrigin: string): Integer;
var
  Name: string;
begin
  // 0 = unbekannt. Größen, die von der Plattform abhängen, nennen sie als Herkunft.
  Name := UpperCase(AType);
  AOrigin := '';
  if MatchStr(Name, ['BYTE', 'SHORTINT', 'ANSICHAR', 'BOOLEAN', 'BYTEBOOL', 'INT8', 'UINT8']) then
    Exit(1);
  if MatchStr(Name, ['WORD', 'SMALLINT', 'CHAR', 'WIDECHAR', 'WORDBOOL', 'INT16', 'UINT16']) then
    Exit(2);
  if MatchStr(Name, ['INTEGER', 'CARDINAL', 'SINGLE', 'LONGBOOL', 'INT32', 'UINT32', 'FIXEDINT', 'FIXEDUINT']) then
    Exit(4);
  if MatchStr(Name, ['INT64', 'UINT64', 'DOUBLE', 'CURRENCY', 'COMP', 'TDATETIME', 'REAL']) then
    Exit(8);
  Result := 0;
  if FPlatform <> '' then
    AOrigin := 'Zielplattform ' + FPlatform;
  if MatchStr(Name, ['POINTER', 'NATIVEINT', 'NATIVEUINT', 'INTPTR', 'UINTPTR', 'PCHAR', 'PANSICHAR', 'PWIDECHAR',
    'STRING', 'UNICODESTRING', 'ANSISTRING', 'RAWBYTESTRING', 'UTF8STRING', 'WIDESTRING', 'TOBJECT', 'TCLASS',
    'IINTERFACE', 'IUNKNOWN', 'THANDLE', 'HWND', 'WPARAM', 'LPARAM', 'LRESULT']) then
    Exit(FPointerSize);
  if MatchStr(Name, ['LONGINT', 'LONGWORD']) then
  begin
    // 64-Bit-POSIX: 8, sonst 4.
    if (FPointerSize = 8) and not FDefines.ContainsKey('MSWINDOWS') then
      Exit(8);
    if FPointerSize > 0 then
      Exit(4);
    Exit(0);
  end;
  if Name = 'EXTENDED' then
  begin
    if FDefines.ContainsKey('MSWINDOWS') and (FPointerSize = 4) then
      Exit(10);
    if FDefines.ContainsKey('MSWINDOWS') or FDefines.ContainsKey('CPUARM') then
      Exit(8);
    if FDefines.ContainsKey('CPUX64') then
      Exit(16);
    Exit(0);
  end;
  if Name = 'VARIANT' then
  begin
    if FPointerSize = 8 then
      Exit(24);
    if FPointerSize = 4 then
      Exit(16);
  end;
  AOrigin := '';
end;

function TExpressionEvaluator.TypeRange(const AType: string; out ALow, AHigh: Double; out AOrigin: string): Boolean;
var
  Name: string;
  Size: Integer;
  Signed: Boolean;
begin
  Name := UpperCase(AType);
  AOrigin := '';
  Result := True;
  if MatchStr(Name, ['BOOLEAN', 'BYTEBOOL', 'WORDBOOL', 'LONGBOOL']) then
  begin
    ALow := 0;
    AHigh := 1;
    Exit;
  end;
  if MatchStr(Name, ['CHAR', 'WIDECHAR']) then
  begin
    ALow := 0;
    AHigh := 65535;
    Exit;
  end;
  if Name = 'ANSICHAR' then
  begin
    ALow := 0;
    AHigh := 255;
    Exit;
  end;
  Signed := MatchStr(Name, ['SHORTINT', 'SMALLINT', 'INTEGER', 'INT8', 'INT16', 'INT32', 'INT64', 'FIXEDINT',
    'NATIVEINT', 'INTPTR', 'LONGINT']);
  if not Signed and not MatchStr(Name, ['BYTE', 'WORD', 'CARDINAL', 'UINT8', 'UINT16', 'UINT32', 'UINT64',
    'FIXEDUINT', 'NATIVEUINT', 'UINTPTR', 'LONGWORD']) then
    Exit(False);
  Size := TypeSize(Name, AOrigin);
  if Size = 0 then
    Exit(False);
  if Signed then
  begin
    AHigh := Power(2, Size * 8 - 1) - 1;
    ALow := -AHigh - 1;
  end
  else
  begin
    ALow := 0;
    AHigh := Power(2, Size * 8) - 1;
  end;
end;

function TExpressionEvaluator.ParseFunction(const AName: string; out AValue: TEvalValue): Boolean;
var
  Argument, Origin: string;
  Size: Integer;
  LowValue, HighValue: Double;
  Token: TPascalToken;
begin
  Result := True;
  if SameText(AName, 'Defined') then
  begin
    Expect('(');
    Argument := ReadName;
    Expect(')');
    AValue := TEvalValue.Make(BooleanValue[FDefines.ContainsKey(UpperCase(Argument))]);
  end
  else if SameText(AName, 'Declared') then
  begin
    Expect('(');
    Argument := ReadName;
    Expect(')');
    AValue := Declared(Argument, Origin);
    AddPart('Declared(' + Argument + ')', BoolText(AValue), Origin);
  end
  else if SameText(AName, 'SizeOf') then
  begin
    Expect('(');
    Argument := ReadName;
    Expect(')');
    Size := TypeSize(Argument, Origin);
    if Size > 0 then
      AValue := TEvalValue.Make(Size)
    else
      AValue := TEvalValue.Unknown;
    AddPart('SizeOf(' + Argument + ')', NumberText(AValue), Origin);
  end
  else if SameText(AName, 'High') or SameText(AName, 'Low') then
  begin
    Expect('(');
    Argument := ReadName;
    Expect(')');
    if not TypeRange(Argument, LowValue, HighValue, Origin) then
      AValue := TEvalValue.Unknown
    else if SameText(AName, 'High') then
      AValue := TEvalValue.Make(HighValue)
    else
      AValue := TEvalValue.Make(LowValue);
    AddPart(AName + '(' + Argument + ')', NumberText(AValue), Origin);
  end
  else if SameText(AName, 'Ord') then
  begin
    Expect('(');
    Token := Peek;
    if (Token.Kind = TPascalTokenKind.StringLiteral) and (Length(Token.Text) = 3) then
    begin
      Inc(FIndex);
      AValue := TEvalValue.Make(Ord(Token.Text[2]));
    end
    else
      AValue := ParseOr;
    Expect(')');
  end
  else
    Result := False;
end;

function TExpressionEvaluator.ParsePrimary: TEvalValue;
var
  Token: TPascalToken;
  Name: string;
  Pair: TPair<string, Double>;
  Number: Double;
begin
  Token := Peek;
  if Token.IsSymbol('(') then
  begin
    Inc(FIndex);
    Result := ParseOr;
    Expect(')');
    Exit;
  end;
  if Token.Kind = TPascalTokenKind.Number then
  begin
    Inc(FIndex);
    if not TryStrToFloat(Token.Text, Number, TFormatSettings.Invariant) then
      Number := StrToIntDef(Token.Text, 0);
    Exit(TEvalValue.Make(Number));
  end;
  if IsWord('True') then
  begin
    Inc(FIndex);
    Exit(TEvalValue.Make(1));
  end;
  if IsWord('False') then
  begin
    Inc(FIndex);
    Exit(TEvalValue.Make(0));
  end;
  Name := ReadName;
  if not AtEnd and Peek.IsSymbol('(') and ParseFunction(Name, Result) then
    Exit;
  if SameText(Name, 'CompilerVersion') or SameText(Name, 'RTLVersion') then
  begin
    if SameText(Name, 'CompilerVersion') and (FOptions.CompilerVersion > 0) then
      Result := TEvalValue.Make(FOptions.CompilerVersion)
    else if SameText(Name, 'RTLVersion') and (FOptions.RTLVersion > 0) then
      Result := TEvalValue.Make(FOptions.RTLVersion)
    else
      Result := TEvalValue.Unknown;
    AddPart(Name, NumberText(Result), ProductOrigin);
    Exit;
  end;
  if VersionConstant(Name, Result) then
  begin
    AddPart(Name, BoolText(Result), ProductOrigin);
    Exit;
  end;
  for Pair in FOptions.Constants do
    if SameText(Pair.Key, Name) then
      Exit(TEvalValue.Make(Pair.Value));
  // Konstante aus dem Code oder einer anderen Unit: Der Wert ist hier nicht bekannt.
  if not AtEnd and Peek.IsSymbol('(') then
    raise EPreprocessorExpression.CreateFmt('Unbekannte Funktion "%s"', [Name]);
  Result := TEvalValue.Unknown;
  AddPart(Name, 'unbekannt', 'Konstante aus dem Code');
end;

{ TPreprocessorRun }

constructor TPreprocessorRun.Create(const AOptions: TPreprocessorOptions);
var
  Define, Entry: string;
  IsDefault: Boolean;
  Letter: Char;
  Switch: TSwitchState;
begin
  inherited Create;
  FOptions := AOptions;
  // Ohne ausdrückliche Angabe folgen CompilerVersion und RTLVersion dem VERnnn der Defines,
  // damit {$IF CompilerVersion >= 36} zu den Projektsymbolen passt.
  if FOptions.CompilerVersion = 0 then
    FOptions.CompilerVersion := TPascalPreprocessor.CompilerVersionFromDefines(AOptions.Defines);
  if FOptions.RTLVersion = 0 then
    FOptions.RTLVersion := FOptions.CompilerVersion;
  FDefines := TDictionary<string, Boolean>.Create;
  FSwitches := TSwitchTable.Create;
  for Define in AOptions.Defines do
    if TPascalPreprocessor.IsSwitchEntry(Define) then
    begin
      // "$R+" aus der .dproj, "$R-*" Vorgabe des Compilers ohne Eintrag dort (#847).
      Entry := Copy(Trim(Define), 2, MaxInt);
      IsDefault := EndsStr('*', Entry);
      if IsDefault then
        Entry := Copy(Entry, 1, Length(Entry) - 1);
      if ParseSwitch(Entry, Letter, Switch.On_) then
      begin
        Switch.Origin := TPascalPreprocessor.SwitchProperty(Letter);
        if IsDefault then
          Switch.Origin := Switch.Origin + ' ' + DefaultSuffix;
        FSwitches.AddOrSetValue(Letter, Switch);
      end;
    end
    else if Trim(Define) <> '' then
      FDefines.AddOrSetValue(UpperCase(Trim(Define)), True);
  FSwitchStack := TObjectStack<TSwitchTable>.Create;
  FChecks := TList<TConditionCheck>.Create;
  FTokens := TList<TPascalToken>.Create;
  FFileIndexes := TList<Integer>.Create;
  FFiles := TList<string>.Create;
  FInactive := TList<TInactiveRange>.Create;
  FConditionals := TList<TConditionalRange>.Create;
  FIssues := TList<TPreprocessorIssue>.Create;
  FDefineSites := TList<TDefineSite>.Create;
  FDirectiveSites := TList<TDirectiveSite>.Create;
  FIncludeStack := TList<string>.Create;
end;

destructor TPreprocessorRun.Destroy;
begin
  FIncludeStack.Free;
  FChecks.Free;
  FSwitchStack.Free;
  FSwitches.Free;
  FDirectiveSites.Free;
  FDefineSites.Free;
  FIssues.Free;
  FInactive.Free;
  FConditionals.Free;
  FFiles.Free;
  FFileIndexes.Free;
  FTokens.Free;
  FDefines.Free;
  inherited;
end;

procedure TPreprocessorRun.AddDefineSite(AFileIndex: Integer; const AToken: TPascalToken; const AName: string;
  AUndefine: Boolean);
var
  Site: TDefineSite;
begin
  if AName = '' then
    Exit;
  Site.FileIndex := AFileIndex;
  Site.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AFileIndex = 0 then
    Site.RootPos := AToken.StartPos
  else
    Site.RootPos := FRootRange.StartPos;
  Site.Name := AName;
  Site.Undefine := AUndefine;
  FDefineSites.Add(Site);
end;

procedure TPreprocessorRun.AddDirectiveSite(AFileIndex: Integer; const AToken: TPascalToken);
var
  Site: TDirectiveSite;
begin
  Site.FileIndex := AFileIndex;
  Site.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AFileIndex = 0 then
    Site.RootPos := AToken.StartPos
  else
    Site.RootPos := FRootRange.StartPos;
  Site.Body := Trim(DirectiveBody(AToken.Text));
  FDirectiveSites.Add(Site);
end;

procedure TPreprocessorRun.AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string;
  AKind: TPreprocessorIssueKind);
var
  Issue: TPreprocessorIssue;
begin
  Issue.Kind := AKind;
  Issue.FileIndex := AFileIndex;
  Issue.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AFileIndex = 0 then
    Issue.RootRange := Issue.Range
  else
    Issue.RootRange := FRootRange;
  Issue.Message := AMessage;
  FIssues.Add(Issue);
end;

procedure TPreprocessorRun.AddCheck(AFileIndex: Integer; const AToken: TPascalToken;
  const ADirective, AExpression: string; AValue: TConditionValue; const AParts: TArray<TConditionPart>);
var
  Check: TConditionCheck;
begin
  Check.FileIndex := AFileIndex;
  Check.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  Check.Directive := ADirective;
  Check.Expression := AExpression;
  Check.Value := AValue;
  Check.Parts := AParts;
  FChecks.Add(Check);
end;

function TPreprocessorRun.EvaluateCondition(const AExpression, ADirective: string; AFileIndex: Integer;
  const AToken: TPascalToken): TConditionValue;
var
  Evaluator: TExpressionEvaluator;
begin
  Evaluator := TExpressionEvaluator.Create(FOptions, FDefines);
  try
    try
      Result := Evaluator.Evaluate(AExpression);
      AddCheck(AFileIndex, AToken, ADirective, AExpression, Result, Evaluator.Parts);
    except
      on E: EPreprocessorExpression do
      begin
        AddIssue(AFileIndex, AToken, 'Ungültiger $IF-Ausdruck: ' + E.Message);
        Result := TConditionValue.No;
      end;
    end;
  finally
    Evaluator.Free;
  end;
end;

function TPreprocessorRun.EvaluateSwitch(const AArgument: string; AFileIndex: Integer;
  const AToken: TPascalToken): TConditionValue;
var
  Letter: Char;
  Wanted: Boolean;
  Switch: TSwitchState;
  Part: TConditionPart;
begin
  // {$IFOPT R+}: Stand aus der .dproj bzw. dem letzten lokalen Schalter davor; sonst unbekannt (#847).
  Part.Text := Trim(AArgument);
  Part.Origin := '';
  if not ParseSwitch(FirstWord(AArgument) + Copy(Trim(AArgument), Length(FirstWord(AArgument)) + 1, 1), Letter,
    Wanted) then
  begin
    AddIssue(AFileIndex, AToken, 'Ungültiger $IFOPT-Schalter: ' + Trim(AArgument));
    Exit(TConditionValue.No);
  end;
  Part.Text := Letter + Copy('-+', Ord(Wanted) + 1, 1);
  if FSwitches.TryGetValue(Letter, Switch) then
  begin
    if Switch.On_ = Wanted then
      Result := TConditionValue.Yes
    else
      Result := TConditionValue.No;
    Part.Value := Letter + Copy('-+', Ord(Switch.On_) + 1, 1);
    Part.Origin := Switch.Origin;
  end
  else
  begin
    Result := TConditionValue.Unknown;
    Part.Value := 'unbekannt';
  end;
  AddCheck(AFileIndex, AToken, 'IFOPT', Trim(AArgument), Result, [Part]);
end;

function TPreprocessorRun.ApplySwitches(const ABody: string; AFileIndex: Integer;
  const AToken: TPascalToken): Boolean;
var
  Parts: TArray<string>;
  Part, Name, Argument, Origin: string;
  Letters: TArray<Char>;
  States: TArray<Boolean>;
  Letter: Char;
  On_: Boolean;
  Index: Integer;
  Switch: TSwitchState;
  SwitchName: TSwitchName;
begin
  // {$R-} und {$R-,Q+} bzw. {$RANGECHECKS OFF} (#847); {$R Datei.res} und {$A8} sind keine Schalter.
  Letters := nil;
  States := nil;
  SplitDirective(ABody, Name, Argument);
  for SwitchName in SwitchNames do
    if (Name = SwitchName.Long) and (SameText(Argument, 'ON') or SameText(Argument, 'OFF')) then
    begin
      Letters := [SwitchName.Letter];
      States := [SameText(Argument, 'ON')];
    end;
  if Letters = nil then
  begin
    Parts := ABody.Split([',']);
    for Part in Parts do
    begin
      if not ParseSwitch(Part, Letter, On_) then
        Exit(False);
      Letters := Letters + [Letter];
      States := States + [On_];
    end;
  end;
  Result := Length(Letters) > 0;
  if AFileIndex = 0 then
    Origin := Format('{$%s} in Zeile %d', [ABody, AToken.StartPos.Line + 1])
  else
    Origin := Format('{$%s} in %s, Zeile %d', [ABody, ExtractFileName(FFiles[AFileIndex]), AToken.StartPos.Line + 1]);
  for Index := 0 to High(Letters) do
  begin
    Switch.On_ := States[Index];
    Switch.Origin := Origin;
    FSwitches.AddOrSetValue(Letters[Index], Switch);
  end;
end;

procedure TPreprocessorRun.Include(const AName: string; AFileIndex, ADepth: Integer; const AToken: TPascalToken);
var
  FileName, Text, Existing: string;
  Index: Integer;
begin
  if AFileIndex = 0 then
    FRootRange := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AName = '' then
  begin
    AddIssue(AFileIndex, AToken, 'Include-Datei fehlt');
    Exit;
  end;
  if not Assigned(FOptions.ResolveInclude) or
    not FOptions.ResolveInclude(AName, FFiles[AFileIndex], FileName, Text) then
  begin
    AddIssue(AFileIndex, AToken, Format('Include-Datei "%s" nicht gefunden', [AName]),
      TPreprocessorIssueKind.IncludeMissing);
    Exit;
  end;
  if ADepth >= FOptions.MaxIncludeDepth then
  begin
    AddIssue(AFileIndex, AToken, 'Include-Dateien zu tief verschachtelt', TPreprocessorIssueKind.IncludeCycle);
    Exit;
  end;
  for Existing in FIncludeStack do
    if SameText(Existing, FileName) then
    begin
      AddIssue(AFileIndex, AToken, Format('Include-Datei "%s" bindet sich selbst ein', [AName]),
        TPreprocessorIssueKind.IncludeCycle);
      Exit;
    end;
  Index := FFiles.Add(FileName);
  FIncludeStack.Add(FileName);
  try
    ProcessText(Text, Index, ADepth + 1);
  finally
    FIncludeStack.Delete(FIncludeStack.Count - 1);
  end;
end;

procedure TPreprocessorRun.ProcessText(const AText: string; AFileIndex, ADepth: Integer);
var
  Stack: TStack<TBranchState>;
  Opening: TStack<TPascalToken>;
  Token: TPascalToken;
  Name, Argument: string;
  State: TBranchState;
  Active, WasActive: Boolean;
  Condition: TConditionValue;
  Saved: TSwitchTable;
  InactiveStart, LastEnd: TTextPosition;
  Range: TInactiveRange;

  /// <summary>Laufenden Zweig bis vor AToken als bedingten Bereich festhalten (nur unter geltendem Elternzweig).</summary>
  procedure CloseBranch(const AState: TBranchState; const AToken: TPascalToken);
  var
    Conditional: TConditionalRange;
  begin
    if not AState.ParentActive or (AState.Text = '') then
      Exit;
    Conditional.FileIndex := AFileIndex;
    Conditional.Range := TTextRange.Create(AState.Start, AToken.StartPos);
    if AState.Outer = '' then
      Conditional.Condition := AState.Text
    else
      Conditional.Condition := AState.Outer + ' und ' + AState.Text;
    Conditional.Active := AState.Active;
    FConditionals.Add(Conditional);
  end;

  /// <summary>Bedingung des innersten geltenden Zweigs, für verschachtelte $IFs.</summary>
  function OuterText: string;
  var
    Top: TBranchState;
  begin
    Result := '';
    if Stack.Count = 0 then
      Exit;
    Top := Stack.Peek;
    if Top.Outer = '' then
      Result := Top.Text
    else if Top.Text = '' then
      Result := Top.Outer
    else
      Result := Top.Outer + ' und ' + Top.Text;
  end;

begin
  Stack := TStack<TBranchState>.Create;
  Opening := TStack<TPascalToken>.Create;
  try
    Active := True;
    InactiveStart := TTextPosition.Create(0, 0);
    LastEnd := InactiveStart;
    for Token in TPascalLexer.Tokenize(AText) do
    begin
      LastEnd := Token.EndPos;
      if Token.Kind <> TPascalTokenKind.Directive then
      begin
        if Active then
        begin
          FTokens.Add(Token);
          FFileIndexes.Add(AFileIndex);
        end;
        Continue;
      end;

      SplitDirective(DirectiveBody(Token.Text), Name, Argument);
      WasActive := Active;

      if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IF') or (Name = 'IFOPT') then
      begin
        State.ParentActive := Active;
        State.InElse := False;
        State.Outer := OuterText;
        if Name = 'IFDEF' then
          State.IfText := UpperCase(FirstWord(Argument))
        else if Name = 'IFNDEF' then
          State.IfText := 'not ' + UpperCase(FirstWord(Argument))
        else if Name = 'IF' then
          State.IfText := Trim(Argument)
        else
          State.IfText := '';
        State.Text := State.IfText;
        State.Start := Token.EndPos;
        if not Active then
          Condition := TConditionValue.No
        else if Name = 'IFDEF' then
          Condition := ConditionOf(FDefines.ContainsKey(UpperCase(FirstWord(Argument))))
        else if Name = 'IFNDEF' then
          Condition := ConditionOf(not FDefines.ContainsKey(UpperCase(FirstWord(Argument))))
        else if Name = 'IF' then
          Condition := EvaluateCondition(Argument, Name, AFileIndex, Token)
        else
          Condition := EvaluateSwitch(Argument, AFileIndex, Token);
        // Unbekannt gilt als aktiv, ohne den Zweig zu „nehmen“: ein {$ELSE} gilt dann auch (#847).
        State.Active := Active and (Condition <> TConditionValue.No);
        State.Taken := Active and (Condition = TConditionValue.Yes);
        Stack.Push(State);
        Opening.Push(Token);
        Active := State.Active;
      end
      else if (Name = 'ELSEIF') or (Name = 'ELSE') then
      begin
        if Stack.Count = 0 then
        begin
          AddIssue(AFileIndex, Token, Format('$%s ohne $IF', [Name]));
          Continue;
        end;
        State := Stack.Pop;
        if State.InElse then
          AddIssue(AFileIndex, Token, Format('$%s nach $ELSE', [Name]));
        CloseBranch(State, Token);
        State.Start := Token.EndPos;
        if Name = 'ELSE' then
        begin
          if State.IfText = '' then
            State.Text := ''
          else if State.IfText.StartsWith('not ') then
            State.Text := Copy(State.IfText, 5, MaxInt)
          else
            State.Text := 'not ' + State.IfText;
        end
        else
          State.Text := Trim(Argument);
        if Name = 'ELSE' then
        begin
          State.Active := State.ParentActive and not State.Taken;
          State.InElse := True;
        end
        else if State.ParentActive and not State.Taken then
        begin
          Condition := EvaluateCondition(Argument, Name, AFileIndex, Token);
          State.Active := Condition <> TConditionValue.No;
          State.Taken := Condition = TConditionValue.Yes;
        end
        else
          State.Active := False;
        Stack.Push(State);
        Active := State.Active;
      end
      else if (Name = 'ENDIF') or (Name = 'IFEND') then
      begin
        if Stack.Count = 0 then
        begin
          AddIssue(AFileIndex, Token, Format('$%s ohne $IF', [Name]));
          Continue;
        end;
        State := Stack.Pop;
        CloseBranch(State, Token);
        Active := State.ParentActive;
        Opening.Pop;
      end
      else if not Active then
        Continue
      else if Name = 'DEFINE' then
      begin
        FDefines.AddOrSetValue(UpperCase(FirstWord(Argument)), True);
        AddDefineSite(AFileIndex, Token, UpperCase(FirstWord(Argument)), False);
      end
      else if Name = 'UNDEF' then
      begin
        FDefines.Remove(UpperCase(FirstWord(Argument)));
        AddDefineSite(AFileIndex, Token, UpperCase(FirstWord(Argument)), True);
      end
      else if ((Name = 'I') and not IsSwitch(Argument)) or (Name = 'INCLUDE') then
        Include(IncludeName(Argument), AFileIndex, ADepth, Token)
      else
      begin
        // Schalterstände für $IFOPT (#847); {$PUSHOPT}/{$POPOPT} sichern bzw. stellen sie wieder her.
        if Name = 'PUSHOPT' then
        begin
          Saved := CopySwitches(FSwitches);
          FSwitchStack.Push(Saved);
        end
        else if Name = 'POPOPT' then
        begin
          if FSwitchStack.Count = 0 then
            AddIssue(AFileIndex, Token, '$POPOPT ohne $PUSHOPT')
          else
          begin
            FSwitches.Free;
            FSwitches := FSwitchStack.Extract;
          end;
        end
        else
          ApplySwitches(DirectiveBody(Token.Text), AFileIndex, Token);
        // Für die Compiler-Schalter an einer Stelle (#558).
        AddDirectiveSite(AFileIndex, Token);
        // Andere Direktiven bleiben für spätere Auswertungen erhalten.
        FTokens.Add(Token);
        FFileIndexes.Add(AFileIndex);
      end;

      if WasActive and not Active then
        InactiveStart := Token.EndPos
      else if not WasActive and Active then
      begin
        Range.FileIndex := AFileIndex;
        Range.Range := TTextRange.Create(InactiveStart, Token.StartPos);
        FInactive.Add(Range);
      end;
    end;

    while Opening.Count > 0 do
      AddIssue(AFileIndex, Opening.Pop, '$ENDIF fehlt');
    if not Active then
    begin
      Range.FileIndex := AFileIndex;
      Range.Range := TTextRange.Create(InactiveStart, LastEnd);
      FInactive.Add(Range);
    end;
  finally
    Opening.Free;
    Stack.Free;
  end;
end;

function TPreprocessorRun.Run(const AText: string): TPreprocessorResult;
var
  Defines: TList<string>;
  Key: string;
begin
  FFiles.Add(FOptions.FileName);
  FIncludeStack.Add(FOptions.FileName);
  ProcessText(AText, 0, 0);
  Result.Tokens := FTokens.ToArray;
  Result.FileIndexes := FFileIndexes.ToArray;
  Result.Files := FFiles.ToArray;
  Result.InactiveRanges := FInactive.ToArray;
  Result.Conditionals := FConditionals.ToArray;
  Result.Issues := FIssues.ToArray;
  Result.DefineSites := FDefineSites.ToArray;
  Result.DirectiveSites := FDirectiveSites.ToArray;
  Result.Checks := FChecks.ToArray;
  Defines := TList<string>.Create;
  try
    for Key in FDefines.Keys do
      Defines.Add(Key);
    Defines.Sort;
    Result.Defines := Defines.ToArray;
  finally
    Defines.Free;
  end;
end;

{ TPascalPreprocessor }

class function TPascalPreprocessor.Process(const AText: string; const AOptions: TPreprocessorOptions): TPreprocessorResult;
var
  Run: TPreprocessorRun;
begin
  Run := TPreprocessorRun.Create(AOptions);
  try
    Result := Run.Run(AText);
  finally
    Run.Free;
  end;
end;

class function TPascalPreprocessor.Evaluate(const AExpression: string; const AOptions: TPreprocessorOptions;
  const ADefines: TArray<string>; out AError: string): Boolean;
var
  Parts: TArray<TConditionPart>;
begin
  Result := Explain(AExpression, AOptions, ADefines, Parts, AError) <> TConditionValue.No;
  if AError <> '' then
    Result := False;
end;

class function TPascalPreprocessor.Explain(const AExpression: string; const AOptions: TPreprocessorOptions;
  const ADefines: TArray<string>; out AParts: TArray<TConditionPart>; out AError: string): TConditionValue;
var
  Defines: TDictionary<string, Boolean>;
  Evaluator: TExpressionEvaluator;
  Define: string;
begin
  AError := '';
  AParts := nil;
  Defines := TDictionary<string, Boolean>.Create;
  try
    for Define in ADefines do
      if not IsSwitchEntry(Define) then
        Defines.AddOrSetValue(UpperCase(Define), True);
    Evaluator := TExpressionEvaluator.Create(AOptions, Defines);
    try
      try
        Result := Evaluator.Evaluate(AExpression);
        AParts := Evaluator.Parts;
      except
        on E: EPreprocessorExpression do
        begin
          AError := E.Message;
          Result := TConditionValue.No;
        end;
      end;
    finally
      Evaluator.Free;
    end;
  finally
    Defines.Free;
  end;
end;

class function TPascalPreprocessor.ProjectSwitches(const AProperties: TArray<TPair<string, string>>): TArray<string>;
var
  SwitchName: TSwitchName;
  Pair: TPair<string, string>;
  Value, Entry: string;
begin
  Result := nil;
  for SwitchName in SwitchNames do
    if SwitchName.Prop <> '' then
    begin
      Entry := '';
      for Pair in AProperties do
        if SameText(Pair.Key, SwitchName.Prop) then
        begin
          // true/false; DCC_DebugInformation auch 0 (keine), 1 (begrenzt), 2 (voll).
          Value := LowerCase(Trim(Pair.Value));
          if (Value = 'true') or (Value = '1') or (Value = '2') then
            Entry := '$' + SwitchName.Letter + '+'
          else if (Value = 'false') or (Value = '0') then
            Entry := '$' + SwitchName.Letter + '-';
        end;
      // Ohne Eintrag gilt die Vorgabe des Compilers, markiert mit "*".
      if Entry = '' then
        Entry := '$' + SwitchName.Letter + SwitchName.Default + '*';
      Result := Result + [Entry];
    end;
end;

class function TPascalPreprocessor.IsSwitchEntry(const ADefine: string): Boolean;
var
  Text: string;
begin
  Text := Trim(ADefine);
  Result := (Text <> '') and (Text[1] = '$');
end;

class function TPascalPreprocessor.SwitchProperty(ALetter: Char): string;
var
  SwitchName: TSwitchName;
begin
  for SwitchName in SwitchNames do
    if SwitchName.Letter = UpCase(ALetter) then
      Exit(SwitchName.Prop);
  Result := '';
end;

class function TPascalPreprocessor.LongSwitchLetter(const AName: string; out ALetter: Char): Boolean;
var
  SwitchName: TSwitchName;
begin
  for SwitchName in SwitchNames do
    if SameText(SwitchName.Long, Trim(AName)) then
    begin
      ALetter := SwitchName.Letter;
      Exit(True);
    end;
  ALetter := #0;
  Result := False;
end;

class function TPascalPreprocessor.SwitchDefault(ALetter: Char): Char;
var
  SwitchName: TSwitchName;
begin
  for SwitchName in SwitchNames do
    if (SwitchName.Letter = UpCase(ALetter)) and (SwitchName.Default <> '') then
      Exit(SwitchName.Default[1]);
  Result := #0;
end;

class procedure TPascalPreprocessor.SetDeclaredProvider(const AProvider: TDeclaredFunc);
begin
  ProviderLock.Enter;
  try
    DeclaredProvider := AProvider;
  finally
    ProviderLock.Leave;
  end;
end;

class function TPascalPreprocessor.ProductName(ACompilerVersion: Double): string;
begin
  // Ab Delphi 11 (CompilerVersion 35) zählt die Hauptversion mit; davor nur die Zahl.
  if ACompilerVersion >= 35 then
    Result := Format('Delphi %d', [Trunc(ACompilerVersion) - 24])
  else
    Result := 'CompilerVersion ' + FloatToStr(ACompilerVersion, TFormatSettings.Invariant);
end;

class function TPascalPreprocessor.CompilerVersionOfBds(ABdsVersion: Double): Double;
begin
  // Gemeinsam mit dem Plugin (#759).
  Result := TTextDefines.CompilerVersionOfBds(ABdsVersion);
end;

class function TPascalPreprocessor.CompilerVersionFromDefines(const ADefines: TArray<string>): Double;
var
  Define, Digits: string;
  Number: Integer;
begin
  for Define in ADefines do
  begin
    Digits := Trim(Define);
    if (Length(Digits) > 3) and SameText(Copy(Digits, 1, 3), 'VER') and
      TryStrToInt(Copy(Digits, 4, MaxInt), Number) and (Number > 0) then
      Exit(Number / 10);
  end;
  Result := 0;
end;

class function TPascalPreprocessor.EditorOptions(const ADefines: TArray<string>): TPreprocessorOptions;
const
  DefaultPlatform = 'Win32';
  DefaultCompilerVersion = 37.0;
begin
  Result := TPreprocessorOptions.Default;
  if Length(ADefines) > 0 then
  begin
    Result.Defines := ADefines;
    Result.CompilerVersion := CompilerVersionFromDefines(ADefines);
  end
  else
  begin
    Result.Defines := PredefinedSymbols(DefaultPlatform, DefaultCompilerVersion);
    Result.CompilerVersion := DefaultCompilerVersion;
  end;
  Result.RTLVersion := Result.CompilerVersion;
end;

class function TPascalPreprocessor.EditorOptions(const ADefines: TArray<string>; const AFileName: string;
  const AResolver: TIncludeResolver): TPreprocessorOptions;
begin
  Result := EditorOptions(ADefines);
  Result.FileName := AFileName;
  Result.ResolveInclude := AResolver;
end;

class function TPascalPreprocessor.MainInactive(const AResult: TPreprocessorResult): TArray<TTextRange>;
var
  Inactive: TInactiveRange;
begin
  Result := nil;
  for Inactive in AResult.InactiveRanges do
    if Inactive.FileIndex = 0 then
      Result := Result + [Inactive.Range];
end;

class function TPascalPreprocessor.MainConditionals(const AResult: TPreprocessorResult): TArray<TConditionalRange>;
var
  Conditional: TConditionalRange;
begin
  Result := nil;
  for Conditional in AResult.Conditionals do
    if Conditional.FileIndex = 0 then
      Result := Result + [Conditional];
end;

class function TPascalPreprocessor.IncludeFileOf(const ADirective: string; out AName: string): Boolean;
var
  Text, Word: string;
  Index: Integer;
begin
  Result := False;
  Text := ADirective;
  if Text.StartsWith('{$') and Text.EndsWith('}') then
    Text := Copy(Text, 3, Length(Text) - 3)
  else if Text.StartsWith('(*$') and Text.EndsWith('*)') then
    Text := Copy(Text, 4, Length(Text) - 5)
  else
    Exit;
  Index := 1;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['A'..'Z', 'a'..'z']) do
    Inc(Index);
  Word := UpperCase(Copy(Text, 1, Index - 1));
  if (Word <> 'I') and (Word <> 'INCLUDE') then
    Exit;
  AName := Trim(Copy(Text, Index, MaxInt));
  Result := (AName <> '') and not CharInSet(AName[1], ['+', '-']);
end;

class function TPascalPreprocessor.HasConditionals(const AText: string): Boolean;
var
  Upper: string;
begin
  Upper := UpperCase(AText);
  Result := (Pos('{$IF', Upper) > 0) or (Pos('(*$IF', Upper) > 0);
end;

class function TPascalPreprocessor.HasIncludes(const AText: string): Boolean;
var
  Upper: string;
  Start, Next: Integer;
begin
  Upper := UpperCase(AText);
  Start := Pos('$I', Upper);
  while Start > 0 do
  begin
    Next := Start + 2;
    if (Start > 1) and CharInSet(Upper[Start - 1], ['{', '*']) and (Next <= Length(Upper)) and
      (CharInSet(Upper[Next], [' ', #9, '''']) or (Copy(Upper, Next, 6) = 'NCLUDE')) then
      Exit(True);
    Start := Pos('$I', Upper, Next);
  end;
  Result := False;
end;

class function TPascalPreprocessor.PredefinedSymbols(const APlatform: string; ACompilerVersion: Double): TArray<string>;
begin
  // Gemeinsam mit dem Plugin (#759): Defines ohne Quelle.
  Result := TTextDefines.Predefined(APlatform, ACompilerVersion);
end;

initialization
  ProviderLock := TCriticalSection.Create;

finalization
  DeclaredProvider := nil;
  FreeAndNil(ProviderLock);

end.
