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
//   Konstanten aus den Optionen, Vergleiche, and/or/xor/not, Klammern. Der
//   Auswerter steht in Atlas.Common.Pascal.Preprocessor.Expressions.
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
    /// <summary>Zielplattform zu den Symbolen ADefines ("Win32", "Win64", "Linux64" …, wie die Plattformnamen
    /// der .dproj); '' ohne Plattformsymbol (#1380).</summary>
    class function PlatformOf(const ADefines: TArray<string>): string; static;
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
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Preprocessor.Expressions,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPreprocessorText = (InvalidIFExpression, InvalidIFOPTSwitch, IncludeFileMissing, IncludeFileNotFound,
    IncludeFileIncludesItself, AndText, AfterELSE, ENDIFMissing, InLineText, InLineText2, IncludeFilesNestedTooDeeply,
    Unknown, CompilerDefault);

const
  cTexts: array[TPreprocessorText] of TAtlasText = (
    (De: 'Ungültiger $IF-Ausdruck: '; En: 'Invalid $IF expression: '),
    (De: 'Ungültiger $IFOPT-Schalter: '; En: 'Invalid $IFOPT switch: '),
    (De: 'Include-Datei fehlt'; En: 'Include file missing'),
    (De: 'Include-Datei "%s" nicht gefunden'; En: 'Include file "%s" not found'),
    (De: 'Include-Datei "%s" bindet sich selbst ein'; En: 'Include file "%s" includes itself'),
    (De: ' und '; En: ' and '),
    (De: '$%s nach $ELSE'; En: '$%s after $ELSE'),
    (De: '$ENDIF fehlt'; En: '$ENDIF missing'),
    (De: '{$%s} in Zeile %d'; En: '{$%s} in line %d'),
    (De: '{$%s} in %s, Zeile %d'; En: '{$%s} in %s, line %d'),
    (De: 'Include-Dateien zu tief verschachtelt'; En: 'Include files nested too deeply'),
    (De: 'unbekannt'; En: 'unknown'),
    (De: '(Vorgabe des Compilers)'; En: '(compiler default)'));

/// <summary>Herkunft eines Schalters ohne Eintrag in der .dproj.</summary>
function DefaultSuffix: string;
begin
  Result := cTexts[TPreprocessorText.CompilerDefault].Text;
end;

type
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
      AKind: TPreprocessorIssueKind); overload;
    procedure AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string); overload;
    procedure AddDirectiveSite(AFileIndex: Integer; const AToken: TPascalToken);
    procedure ProcessText(const AText: string; AFileIndex, ADepth: Integer);
    procedure Include(const AName: string; AFileIndex, ADepth: Integer; const AToken: TPascalToken);
    function EvaluateCondition(const AExpression, ADirective: string; AFileIndex: Integer;
      const AToken: TPascalToken): TConditionValue;
    function EvaluateSwitch(const AArgument: string; AFileIndex: Integer; const AToken: TPascalToken): TConditionValue;
    function ApplySwitches(const ABody: string; AFileIndex: Integer; const AToken: TPascalToken): Boolean;
    procedure AddCheck(AFileIndex: Integer; const AToken: TPascalToken; const ADirective, AExpression: string;
      AValue: TConditionValue; const AParts: TArray<TConditionPart>);
    /// <summary>Symbol oder Schaltereintrag ("$R+", "$R-*") aus den Optionen.</summary>
    procedure AddProjectDefine(const ADefine: string);
  public
    constructor Create(const AOptions: TPreprocessorOptions);
    destructor Destroy; override;
    function Run(const AText: string): TPreprocessorResult;
  end;

  /// <summary>Bedingte Zweige und Direktiven einer Datei (Hauptdatei oder Include-Datei) für
  /// TPreprocessorRun.ProcessText; Ergebnisse landen im Lauf.</summary>
  TPreprocessorFileScan = class
  private
    FRun: TPreprocessorRun;
    FFileIndex: Integer;
    FDepth: Integer;
    FStack: TStack<TBranchState>;
    /// <summary>Öffnende $IF-Direktiven, für "$ENDIF fehlt".</summary>
    FOpening: TStack<TPascalToken>;
    FActive: Boolean;
    FInactiveStart: TTextPosition;
    procedure AddToken(const AToken: TPascalToken);
    /// <summary>Inaktiver Bereich von FInactiveStart bis AEnd.</summary>
    procedure AddInactive(const AEnd: TTextPosition);
    /// <summary>Laufenden Zweig bis vor AToken als bedingten Bereich festhalten (nur unter geltendem
    /// Elternzweig).</summary>
    procedure CloseBranch(const AState: TBranchState; const AToken: TPascalToken);
    /// <summary>Bedingung des innersten geltenden Zweigs, für verschachtelte $IFs.</summary>
    function OuterText: string;
    /// <summary>Bedingung eines $IFDEF, $IFNDEF oder $IF als Text; '' bei $IFOPT.</summary>
    function IfText(const AName, AArgument: string): string;
    function IfCondition(const AName, AArgument: string; const AToken: TPascalToken): TConditionValue;
    procedure OpenIf(const AName, AArgument: string; const AToken: TPascalToken);
    /// <summary>Bedingung des $ELSE-Zweigs als Text.</summary>
    function ElseText(const AState: TBranchState): string;
    /// <summary>$ELSE oder $ELSEIF.</summary>
    procedure NextBranch(const AName, AArgument: string; const AToken: TPascalToken);
    procedure EndIf(const AName: string; const AToken: TPascalToken);
    /// <summary>$DEFINE, $UNDEF, $I und Schalter in einem aktiven Zweig.</summary>
    procedure ActiveDirective(const AName, AArgument: string; const AToken: TPascalToken);
    procedure SwitchDirective(const AName: string; const AToken: TPascalToken);
    procedure Directive(const AToken: TPascalToken);
  public
    constructor Create(ARun: TPreprocessorRun; AFileIndex, ADepth: Integer);
    destructor Destroy; override;
    procedure Scan(const AText: string);
  end;

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
  begin
    Exit;
  end;
  ALetter := UpCase(Text[1]);
  AOn := Text[2] = '+';
end;

function CopySwitches(ASource: TSwitchTable): TSwitchTable;
var
  Letter: Char;
begin
  Result := TSwitchTable.Create;
  for Letter in ASource.Keys do
  begin
    Result.Add(Letter, ASource[Letter]);
  end;
end;

function ConditionOf(AValue: Boolean): TConditionValue;
begin
  if AValue then
  begin
    Result := TConditionValue.Yes;
  end
  else
  begin
    Result := TConditionValue.No;
  end;
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

/// <summary>Einstellungen des $IF-Auswerters aus den Optionen und den Symbolen ADefines (Schlüssel in
/// Großbuchstaben); Declared ohne Options.Declared fragt den Provider (SetDeclaredProvider).</summary>
function ExpressionSettings(const AOptions: TPreprocessorOptions;
  ADefines: TDictionary<string, Boolean>): TExpressionSettings;
begin
  Result.CompilerVersion := AOptions.CompilerVersion;
  Result.RTLVersion := AOptions.RTLVersion;
  Result.Constants := AOptions.Constants;
  Result.Declared := AOptions.Declared;
  if not Assigned(Result.Declared) then
  begin
    Result.Declared := CurrentDeclaredProvider();
  end;
  Result.ProductName := '';
  if AOptions.CompilerVersion > 0 then
  begin
    Result.ProductName := TPascalPreprocessor.ProductName(AOptions.CompilerVersion);
  end;
  Result.Platform := TPascalPreprocessor.PlatformOf(ADefines.Keys.ToArray);
end;

function DirectiveBody(const AText: string): string;
begin
  // '{$IFDEF X}' bzw. '(*$IFDEF X*)' → 'IFDEF X'
  if (Length(AText) >= 2) and (AText[1] = '{') then
  begin
    Result := Copy(AText, 3, MaxInt);
    if (Result <> '') and (Result[Length(Result)] = '}') then
    begin
      Delete(Result, Length(Result), 1);
    end;
  end
  else
  begin
    Result := Copy(AText, 4, MaxInt);
    if (Length(Result) >= 2) and (Copy(Result, Length(Result) - 1, 2) = '*)') then
    begin
      Delete(Result, Length(Result) - 1, 2);
    end;
  end;
  Result := Trim(Result);
end;

procedure SplitDirective(const ABody: string; out AName, AArgument: string);
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(ABody)) and CharInSet(ABody[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Inc(I);
  end;
  AName := UpperCase(Copy(ABody, 1, I - 1));
  AArgument := Trim(Copy(ABody, I, MaxInt));
end;

function FirstWord(const AArgument: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(AArgument)) and CharInSet(AArgument[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
  begin
    Inc(I);
  end;
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
    begin
      Result := Copy(Result, 2, Stop - 1);
    end
    else
    begin
      Result := Copy(Result, 2, MaxInt);
    end;
  end
  else
  begin
    Stop := Pos(' ', Result);
    if Stop > 0 then
    begin
      Result := Copy(Result, 1, Stop - 1);
    end;
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

{ TPreprocessorRun }

procedure TPreprocessorRun.AddProjectDefine(const ADefine: string);
var
  mEntry: string;
  mIsDefault: Boolean;
  mLetter: Char;
  mSwitch: TSwitchState;
begin
  if not TPascalPreprocessor.IsSwitchEntry(ADefine) then
  begin
    if Trim(ADefine) <> '' then
    begin
      FDefines.AddOrSetValue(UpperCase(Trim(ADefine)), True);
    end;
    Exit;
  end;
  // "$R+" aus der .dproj, "$R-*" Vorgabe des Compilers ohne Eintrag dort (#847).
  mEntry := Copy(Trim(ADefine), 2, MaxInt);
  mIsDefault := EndsStr('*', mEntry);
  if mIsDefault then
  begin
    mEntry := Copy(mEntry, 1, Length(mEntry) - 1);
  end;
  if not ParseSwitch(mEntry, mLetter, mSwitch.On_) then
  begin
    Exit;
  end;
  mSwitch.Origin := TPascalPreprocessor.SwitchProperty(mLetter);
  if mIsDefault then
  begin
    mSwitch.Origin := mSwitch.Origin + ' ' + DefaultSuffix;
  end;
  FSwitches.AddOrSetValue(mLetter, mSwitch);
end;

constructor TPreprocessorRun.Create(const AOptions: TPreprocessorOptions);
var
  Define: string;
begin
  inherited Create;
  FOptions := AOptions;
  // Ohne ausdrückliche Angabe folgen CompilerVersion und RTLVersion dem VERnnn der Defines,
  // damit {$IF CompilerVersion >= 36} zu den Projektsymbolen passt.
  if FOptions.CompilerVersion = 0 then
  begin
    FOptions.CompilerVersion := TPascalPreprocessor.CompilerVersionFromDefines(AOptions.Defines);
  end;
  if FOptions.RTLVersion = 0 then
  begin
    FOptions.RTLVersion := FOptions.CompilerVersion;
  end;
  FDefines := TDictionary<string, Boolean>.Create;
  FSwitches := TSwitchTable.Create;
  for Define in AOptions.Defines do
  begin
    AddProjectDefine(Define);
  end;
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
  begin
    Exit;
  end;
  Site.FileIndex := AFileIndex;
  Site.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AFileIndex = 0 then
  begin
    Site.RootPos := AToken.StartPos;
  end
  else
  begin
    Site.RootPos := FRootRange.StartPos;
  end;
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
  begin
    Site.RootPos := AToken.StartPos;
  end
  else
  begin
    Site.RootPos := FRootRange.StartPos;
  end;
  Site.Body := Trim(DirectiveBody(AToken.Text));
  FDirectiveSites.Add(Site);
end;

procedure TPreprocessorRun.AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string);
begin
  AddIssue(AFileIndex, AToken, AMessage, TPreprocessorIssueKind.General);
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
  begin
    Issue.RootRange := Issue.Range;
  end
  else
  begin
    Issue.RootRange := FRootRange;
  end;
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
  Evaluator := TExpressionEvaluator.Create(ExpressionSettings(FOptions, FDefines), FDefines);
  try
    try
      Result := Evaluator.Evaluate(AExpression);
      AddCheck(AFileIndex, AToken, ADirective, AExpression, Result, Evaluator.Parts);
    except
      on E: EPreprocessorExpression do
      begin
        AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.InvalidIFExpression].Text + E.Message);
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
    AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.InvalidIFOPTSwitch].Text + Trim(AArgument));
    Exit(TConditionValue.No);
  end;
  Part.Text := Letter + Copy('-+', Ord(Wanted) + 1, 1);
  if FSwitches.TryGetValue(Letter, Switch) then
  begin
    if Switch.On_ = Wanted then
    begin
      Result := TConditionValue.Yes;
    end
    else
    begin
      Result := TConditionValue.No;
    end;
    Part.Value := Letter + Copy('-+', Ord(Switch.On_) + 1, 1);
    Part.Origin := Switch.Origin;
  end
  else
  begin
    Result := TConditionValue.Unknown;
    Part.Value := cTexts[TPreprocessorText.Unknown].Text;
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
  begin
    if (Name = SwitchName.Long) and (SameText(Argument, 'ON') or SameText(Argument, 'OFF')) then
    begin
      Letters := [SwitchName.Letter];
      States := [SameText(Argument, 'ON')];
    end;
  end;
  if Letters = nil then
  begin
    Parts := ABody.Split([',']);
    for Part in Parts do
    begin
      if not ParseSwitch(Part, Letter, On_) then
      begin
        Exit(False);
      end;
      Letters := Letters + [Letter];
      States := States + [On_];
    end;
  end;
  Result := Length(Letters) > 0;
  if AFileIndex = 0 then
  begin
    Origin := cTexts[TPreprocessorText.InLineText].Fmt([ABody, AToken.StartPos.Line + 1]);
  end
  else
  begin
    Origin := cTexts[TPreprocessorText.InLineText2].Fmt([ABody, ExtractFileName(FFiles[AFileIndex]),
      AToken.StartPos.Line + 1]);
  end;
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
  begin
    FRootRange := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  end;
  if AName = '' then
  begin
    AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.IncludeFileMissing].Text);
    Exit;
  end;
  if not Assigned(FOptions.ResolveInclude) or
    not FOptions.ResolveInclude(AName, FFiles[AFileIndex], FileName, Text) then
  begin
    AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.IncludeFileNotFound].Fmt([AName]),
      TPreprocessorIssueKind.IncludeMissing);
    Exit;
  end;
  if ADepth >= FOptions.MaxIncludeDepth then
  begin
    AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.IncludeFilesNestedTooDeeply].Text,
      TPreprocessorIssueKind.IncludeCycle);
    Exit;
  end;
  for Existing in FIncludeStack do
  begin
    if SameText(Existing, FileName) then
    begin
      AddIssue(AFileIndex, AToken, cTexts[TPreprocessorText.IncludeFileIncludesItself].Fmt([AName]),
        TPreprocessorIssueKind.IncludeCycle);
      Exit;
    end;
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
  mScan: TPreprocessorFileScan;
begin
  mScan := TPreprocessorFileScan.Create(Self, AFileIndex, ADepth);
  try
    mScan.Scan(AText);
  finally
    mScan.Free;
  end;
end;

{ TPreprocessorFileScan }

constructor TPreprocessorFileScan.Create(ARun: TPreprocessorRun; AFileIndex, ADepth: Integer);
begin
  inherited Create;
  FRun := ARun;
  FFileIndex := AFileIndex;
  FDepth := ADepth;
  FStack := TStack<TBranchState>.Create;
  FOpening := TStack<TPascalToken>.Create;
end;

destructor TPreprocessorFileScan.Destroy;
begin
  FOpening.Free;
  FStack.Free;
  inherited Destroy;
end;

procedure TPreprocessorFileScan.AddToken(const AToken: TPascalToken);
begin
  FRun.FTokens.Add(AToken);
  FRun.FFileIndexes.Add(FFileIndex);
end;

procedure TPreprocessorFileScan.AddInactive(const AEnd: TTextPosition);
var
  mRange: TInactiveRange;
begin
  mRange.FileIndex := FFileIndex;
  mRange.Range := TTextRange.Create(FInactiveStart, AEnd);
  FRun.FInactive.Add(mRange);
end;

procedure TPreprocessorFileScan.CloseBranch(const AState: TBranchState; const AToken: TPascalToken);
var
  mConditional: TConditionalRange;
begin
  if not AState.ParentActive or (AState.Text = '') then
  begin
    Exit;
  end;
  mConditional.FileIndex := FFileIndex;
  mConditional.Range := TTextRange.Create(AState.Start, AToken.StartPos);
  if AState.Outer = '' then
  begin
    mConditional.Condition := AState.Text;
  end
  else
  begin
    mConditional.Condition := AState.Outer + cTexts[TPreprocessorText.AndText].Text + AState.Text;
  end;
  mConditional.Active := AState.Active;
  FRun.FConditionals.Add(mConditional);
end;

function TPreprocessorFileScan.OuterText: string;
var
  mTop: TBranchState;
begin
  Result := '';
  if FStack.Count = 0 then
  begin
    Exit;
  end;
  mTop := FStack.Peek;
  if mTop.Outer = '' then
  begin
    Result := mTop.Text;
  end
  else if mTop.Text = '' then
  begin
    Result := mTop.Outer;
  end
  else
  begin
    Result := mTop.Outer + cTexts[TPreprocessorText.AndText].Text + mTop.Text;
  end;
end;

function TPreprocessorFileScan.IfText(const AName, AArgument: string): string;
begin
  if AName = 'IFDEF' then
  begin
    Result := UpperCase(FirstWord(AArgument));
  end
  else if AName = 'IFNDEF' then
  begin
    Result := 'not ' + UpperCase(FirstWord(AArgument));
  end
  else if AName = 'IF' then
  begin
    Result := Trim(AArgument);
  end
  else
  begin
    Result := '';
  end;
end;

function TPreprocessorFileScan.IfCondition(const AName, AArgument: string;
  const AToken: TPascalToken): TConditionValue;
begin
  if AName = 'IFDEF' then
  begin
    Result := ConditionOf(FRun.FDefines.ContainsKey(UpperCase(FirstWord(AArgument))));
  end
  else if AName = 'IFNDEF' then
  begin
    Result := ConditionOf(not FRun.FDefines.ContainsKey(UpperCase(FirstWord(AArgument))));
  end
  else if AName = 'IF' then
  begin
    Result := FRun.EvaluateCondition(AArgument, AName, FFileIndex, AToken);
  end
  else
  begin
    Result := FRun.EvaluateSwitch(AArgument, FFileIndex, AToken);
  end;
end;

procedure TPreprocessorFileScan.OpenIf(const AName, AArgument: string; const AToken: TPascalToken);
var
  mState: TBranchState;
  mCondition: TConditionValue;
begin
  mState.ParentActive := FActive;
  mState.InElse := False;
  mState.Outer := OuterText;
  mState.IfText := IfText(AName, AArgument);
  mState.Text := mState.IfText;
  mState.Start := AToken.EndPos;
  mCondition := TConditionValue.No;
  if FActive then
  begin
    mCondition := IfCondition(AName, AArgument, AToken);
  end;
  // Unbekannt gilt als aktiv, ohne den Zweig zu „nehmen“: ein {$ELSE} gilt dann auch (#847).
  mState.Active := FActive and (mCondition <> TConditionValue.No);
  mState.Taken := FActive and (mCondition = TConditionValue.Yes);
  FStack.Push(mState);
  FOpening.Push(AToken);
  FActive := mState.Active;
end;

function TPreprocessorFileScan.ElseText(const AState: TBranchState): string;
begin
  if AState.IfText = '' then
  begin
    Result := '';
  end
  else if AState.IfText.StartsWith('not ') then
  begin
    Result := Copy(AState.IfText, 5, MaxInt);
  end
  else
  begin
    Result := 'not ' + AState.IfText;
  end;
end;

procedure TPreprocessorFileScan.NextBranch(const AName, AArgument: string; const AToken: TPascalToken);
var
  mState: TBranchState;
  mCondition: TConditionValue;
begin
  if FStack.Count = 0 then
  begin
    FRun.AddIssue(FFileIndex, AToken, Format('$%s ohne $IF', [AName]));
    Exit;
  end;
  mState := FStack.Pop;
  if mState.InElse then
  begin
    FRun.AddIssue(FFileIndex, AToken, cTexts[TPreprocessorText.AfterELSE].Fmt([AName]));
  end;
  CloseBranch(mState, AToken);
  mState.Start := AToken.EndPos;
  if AName = 'ELSE' then
  begin
    mState.Text := ElseText(mState);
    mState.Active := mState.ParentActive and not mState.Taken;
    mState.InElse := True;
  end
  else
  begin
    mState.Text := Trim(AArgument);
    mState.Active := False;
    if mState.ParentActive and not mState.Taken then
    begin
      mCondition := FRun.EvaluateCondition(AArgument, AName, FFileIndex, AToken);
      mState.Active := mCondition <> TConditionValue.No;
      mState.Taken := mCondition = TConditionValue.Yes;
    end;
  end;
  FStack.Push(mState);
  FActive := mState.Active;
end;

procedure TPreprocessorFileScan.EndIf(const AName: string; const AToken: TPascalToken);
var
  mState: TBranchState;
begin
  if FStack.Count = 0 then
  begin
    FRun.AddIssue(FFileIndex, AToken, Format('$%s ohne $IF', [AName]));
    Exit;
  end;
  mState := FStack.Pop;
  CloseBranch(mState, AToken);
  FActive := mState.ParentActive;
  FOpening.Pop;
end;

procedure TPreprocessorFileScan.SwitchDirective(const AName: string; const AToken: TPascalToken);
begin
  // Schalterstände für $IFOPT (#847); {$PUSHOPT}/{$POPOPT} sichern bzw. stellen sie wieder her.
  if AName = 'PUSHOPT' then
  begin
    FRun.FSwitchStack.Push(CopySwitches(FRun.FSwitches));
  end
  else if (AName = 'POPOPT') and (FRun.FSwitchStack.Count = 0) then
  begin
    FRun.AddIssue(FFileIndex, AToken, '$POPOPT ohne $PUSHOPT');
  end
  else if AName = 'POPOPT' then
  begin
    FRun.FSwitches.Free;
    FRun.FSwitches := FRun.FSwitchStack.Extract;
  end
  else
  begin
    FRun.ApplySwitches(DirectiveBody(AToken.Text), FFileIndex, AToken);
  end;
  // Für die Compiler-Schalter an einer Stelle (#558).
  FRun.AddDirectiveSite(FFileIndex, AToken);
  // Andere Direktiven bleiben für spätere Auswertungen erhalten.
  AddToken(AToken);
end;

procedure TPreprocessorFileScan.ActiveDirective(const AName, AArgument: string; const AToken: TPascalToken);
var
  mSymbol: string;
begin
  mSymbol := UpperCase(FirstWord(AArgument));
  if AName = 'DEFINE' then
  begin
    FRun.FDefines.AddOrSetValue(mSymbol, True);
    FRun.AddDefineSite(FFileIndex, AToken, mSymbol, False);
  end
  else if AName = 'UNDEF' then
  begin
    FRun.FDefines.Remove(mSymbol);
    FRun.AddDefineSite(FFileIndex, AToken, mSymbol, True);
  end
  else if ((AName = 'I') and not IsSwitch(AArgument)) or (AName = 'INCLUDE') then
  begin
    FRun.Include(IncludeName(AArgument), FFileIndex, FDepth, AToken);
  end
  else
  begin
    SwitchDirective(AName, AToken);
  end;
end;

procedure TPreprocessorFileScan.Directive(const AToken: TPascalToken);
var
  mName, mArgument: string;
  mWasActive: Boolean;
begin
  SplitDirective(DirectiveBody(AToken.Text), mName, mArgument);
  mWasActive := FActive;
  if MatchStr(mName, ['IFDEF', 'IFNDEF', 'IF', 'IFOPT']) then
  begin
    OpenIf(mName, mArgument, AToken);
  end
  else if (mName = 'ELSEIF') or (mName = 'ELSE') then
  begin
    NextBranch(mName, mArgument, AToken);
  end
  else if (mName = 'ENDIF') or (mName = 'IFEND') then
  begin
    EndIf(mName, AToken);
  end
  else if FActive then
  begin
    ActiveDirective(mName, mArgument, AToken);
  end;
  if mWasActive and not FActive then
  begin
    FInactiveStart := AToken.EndPos;
  end
  else if not mWasActive and FActive then
  begin
    AddInactive(AToken.StartPos);
  end;
end;

procedure TPreprocessorFileScan.Scan(const AText: string);
var
  mToken: TPascalToken;
  mLastEnd: TTextPosition;
begin
  FActive := True;
  FInactiveStart := TTextPosition.Create(0, 0);
  mLastEnd := FInactiveStart;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    mLastEnd := mToken.EndPos;
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      Directive(mToken);
    end
    else if FActive then
    begin
      AddToken(mToken);
    end;
  end;
  while FOpening.Count > 0 do
  begin
    FRun.AddIssue(FFileIndex, FOpening.Pop, cTexts[TPreprocessorText.ENDIFMissing].Text);
  end;
  if not FActive then
  begin
    AddInactive(mLastEnd);
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
    begin
      Defines.Add(Key);
    end;
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
  begin
    Result := False;
  end;
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
    begin
      if not IsSwitchEntry(Define) then
      begin
        Defines.AddOrSetValue(UpperCase(Define), True);
      end;
    end;
    Evaluator := TExpressionEvaluator.Create(ExpressionSettings(AOptions, Defines), Defines);
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

/// <summary>"+" bzw. "-" zum Wert einer Schaltereigenschaft der .dproj (true/false; DCC_DebugInformation auch
/// 0 = keine, 1 = begrenzt, 2 = voll); '' bei anderen Werten.</summary>
function PropertySign(const AValue: string): string;
var
  mValue: string;
begin
  mValue := LowerCase(Trim(AValue));
  if MatchStr(mValue, ['true', '1', '2']) then
  begin
    Result := '+';
  end
  else if MatchStr(mValue, ['false', '0']) then
  begin
    Result := '-';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Eintrag "$R+" für den Schalter ASwitch aus AProperties; ohne Eintrag die Vorgabe des Compilers,
/// markiert mit "*".</summary>
function ProjectSwitchEntry(const ASwitch: TSwitchName; const AProperties: TArray<TPair<string, string>>): string;
var
  mPair: TPair<string, string>;
  mSign: string;
begin
  Result := '';
  for mPair in AProperties do
  begin
    mSign := '';
    if SameText(mPair.Key, ASwitch.Prop) then
    begin
      mSign := PropertySign(mPair.Value);
    end;
    if mSign <> '' then
    begin
      Result := '$' + ASwitch.Letter + mSign;
    end;
  end;
  if Result = '' then
  begin
    Result := '$' + ASwitch.Letter + ASwitch.Default + '*';
  end;
end;

class function TPascalPreprocessor.ProjectSwitches(const AProperties: TArray<TPair<string, string>>): TArray<string>;
var
  SwitchName: TSwitchName;
begin
  Result := nil;
  for SwitchName in SwitchNames do
  begin
    if SwitchName.Prop <> '' then
    begin
      Result := Result + [ProjectSwitchEntry(SwitchName, AProperties)];
    end;
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
  begin
    if SwitchName.Letter = UpCase(ALetter) then
    begin
      Exit(SwitchName.Prop);
    end;
  end;
  Result := '';
end;

class function TPascalPreprocessor.LongSwitchLetter(const AName: string; out ALetter: Char): Boolean;
var
  SwitchName: TSwitchName;
begin
  for SwitchName in SwitchNames do
  begin
    if SameText(SwitchName.Long, Trim(AName)) then
    begin
      ALetter := SwitchName.Letter;
      Exit(True);
    end;
  end;
  ALetter := #0;
  Result := False;
end;

class function TPascalPreprocessor.SwitchDefault(ALetter: Char): Char;
var
  SwitchName: TSwitchName;
begin
  for SwitchName in SwitchNames do
  begin
    if (SwitchName.Letter = UpCase(ALetter)) and (SwitchName.Default <> '') then
    begin
      Exit(SwitchName.Default[1]);
    end;
  end;
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
  begin
    Result := Format('Delphi %d', [Trunc(ACompilerVersion) - 24]);
  end
  else
  begin
    Result := 'CompilerVersion ' + FloatToStr(ACompilerVersion, TFormatSettings.Invariant);
  end;
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
    begin
      Exit(Number / 10);
    end;
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
  begin
    if Inactive.FileIndex = 0 then
    begin
      Result := Result + [Inactive.Range];
    end;
  end;
end;

class function TPascalPreprocessor.MainConditionals(const AResult: TPreprocessorResult): TArray<TConditionalRange>;
var
  Conditional: TConditionalRange;
begin
  Result := nil;
  for Conditional in AResult.Conditionals do
  begin
    if Conditional.FileIndex = 0 then
    begin
      Result := Result + [Conditional];
    end;
  end;
end;

class function TPascalPreprocessor.IncludeFileOf(const ADirective: string; out AName: string): Boolean;
var
  Text, Word: string;
  Index: Integer;
begin
  Result := False;
  Text := ADirective;
  if Text.StartsWith('{$') and Text.EndsWith('}') then
  begin
    Text := Copy(Text, 3, Length(Text) - 3);
  end
  else if Text.StartsWith('(*$') and Text.EndsWith('*)') then
  begin
    Text := Copy(Text, 4, Length(Text) - 5);
  end
  else
  begin
    Exit;
  end;
  Index := 1;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(Index);
  end;
  Word := UpperCase(Copy(Text, 1, Index - 1));
  if (Word <> 'I') and (Word <> 'INCLUDE') then
  begin
    Exit;
  end;
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
    begin
      Exit(True);
    end;
    Start := Pos('$I', Upper, Next);
  end;
  Result := False;
end;

class function TPascalPreprocessor.PlatformOf(const ADefines: TArray<string>): string;

  function Has(const AName: string): Boolean;
  var
    mDefine: string;
  begin
    for mDefine in ADefines do
    begin
      if SameText(Trim(mDefine), AName) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

begin
  if Has('WIN64') then
  begin
    Result := 'Win64';
  end
  else if Has('WIN32') then
  begin
    Result := 'Win32';
  end
  else if Has('LINUX64') then
  begin
    Result := 'Linux64';
  end
  else if Has('MACOS64') and Has('CPUARM64') then
  begin
    Result := 'OSXARM64';
  end
  else if Has('MACOS64') and not Has('IOS') then
  begin
    Result := 'OSX64';
  end
  else if Has('IOS64') then
  begin
    Result := 'iOSDevice64';
  end
  else if Has('ANDROID64') then
  begin
    Result := 'Android64';
  end
  else if Has('ANDROID') then
  begin
    Result := 'Android';
  end
  else
  begin
    Result := '';
  end;
end;

class function TPascalPreprocessor.PredefinedSymbols(const APlatform: string; ACompilerVersion: Double): TArray<string>;
begin
  // Gemeinsam mit dem Plugin (#759): Defines ohne Quelle.
  Result := TTextDefines.Predefined(APlatform, ACompilerVersion);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.Preprocessor', cTexts);
  ProviderLock := TCriticalSection.Create;

finalization
  DeclaredProvider := nil;
  FreeAndNil(ProviderLock);

end.
