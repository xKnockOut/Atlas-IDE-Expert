unit Argus.Common.Lsp.KeywordReference;

// Hover über Schlüsselwörtern und Direktiven (#187): Kurztext und DocWiki-Link
// für seltene Sprachelemente wie absolute, reintroduce, strict private,
// class var, message, implements, stored, default, dispid, inline, overload.
// Ergänzt die Tabelle der Compiler-Direktiven (#102) und nutzt deren
// Linkschema (TCompilerDirectives.Url, Release-Name je Delphi-Version, #27).
//
// Zweiwortige Elemente (strict private, class var, is not, not in) werden
// über die Nachbartoken erkannt. Elemente ab Delphi 13 (Bedingungsausdruck
// if … then … else, is not, not in) tragen die Mindestversion; in Projekten
// mit älterer Version nennt der Hover, dass das Element dort fehlt.
// Alltägliche Wörter wie begin, if oder var stehen auf CommonWords und
// bekommen keinen Hover.

interface

uses
  System.SysUtils,
  Argus.Common.Documents.Contract;

type
  TKeywordInfo = record
    /// <summary>Schlüsselwort in Kleinbuchstaben, zweiwortig mit Leerzeichen ("strict private").</summary>
    Name: string;
    /// <summary>Art für die Überschrift, z. B. "Direktive" oder "reserviertes Wort".</summary>
    Kind: string;
    /// <summary>Kurztext auf Deutsch.</summary>
    Text: string;
    /// <summary>Seite in der DocWiki, ggf. mit Anker.</summary>
    Topic: string;
    /// <summary>Mindestversion als BDS-Nummer ("37.0" = Delphi 13), '' = schon immer.</summary>
    MinVersion: string;
  end;

  TKeywordReference = class
  public const
    /// <summary>Wörter, die so alltäglich sind, dass ein Hover nur stört.</summary>
    CommonWords: array[0..43] of string = (
      'and', 'array', 'as', 'begin', 'case', 'class', 'const', 'div', 'do', 'downto', 'else', 'end',
      'except', 'finally', 'for', 'function', 'if', 'implementation', 'in', 'interface', 'is', 'mod',
      'nil', 'not', 'of', 'or', 'procedure', 'program', 'raise', 'record', 'repeat', 'set', 'string',
      'then', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'xor', 'private');
  public
    /// <summary>Alle Einträge der Tabelle.</summary>
    class function All: TArray<TKeywordInfo>; static;
    /// <summary>Eintrag zu AName (ohne Groß-/Kleinschreibung).</summary>
    class function Find(const AName: string; out AInfo: TKeywordInfo): Boolean; static;
    /// <summary>Markdown für AInfo mit Link für ADelphiVersion und ggf. Versionshinweis.</summary>
    class function Describe(const AInfo: TKeywordInfo; const ADelphiVersion: string): string; static;
    /// <summary>Hover über dem Schlüsselwort an APosition; False, wenn dort keines aus der Tabelle steht.</summary>
    class function HoverAt(const AText: string; const APosition: TTextPosition; const ADelphiVersion: string;
      out AMarkdown: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Pascal.LanguageFeatures,
  Argus.Common.Lsp.CompilerDirectives;

const
  Delphi13 = '37.0';
  Methods = 'Methods_(Delphi)';
  Properties = 'Properties_(Delphi)';
  Classes = 'Classes_and_Objects_(Delphi)';
  Routines = 'Procedures_and_Functions_(Delphi)';
  Hints = 'Declarations_and_Statements_(Delphi)#Hinting_Directives';
  Expressions = 'Expressions_(Delphi)';

function K(const AName, AKind, AText, ATopic: string; const AMinVersion: string = ''): TKeywordInfo;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Topic := ATopic;
  Result.MinVersion := AMinVersion;
end;

var
  Keywords: TArray<TKeywordInfo>;

procedure InitKeywords;
const
  Directive = 'Direktive';
  Reserved = 'reserviertes Wort';
begin
  Keywords := [
    // Methoden und Routinen
    K('reintroduce', Directive, 'Verdeckt eine virtuelle Methode des Vorfahren bewusst, ohne sie zu überschreiben; ' +
      'unterdrückt die Warnung W1010.', Methods),
    K('overload', Directive, 'Erlaubt mehrere Routinen gleichen Namens mit unterschiedlichen Parametern.',
      Routines + '#Overloading_Procedures_and_Functions'),
    K('override', Directive, 'Überschreibt eine virtuelle oder dynamische Methode des Vorfahren.', Methods),
    K('virtual', Directive, 'Methode kann in Nachfahren überschrieben werden (Aufruf über die VMT).', Methods),
    K('dynamic', Directive, 'Wie virtual, aber platzsparender und langsamer (Aufruf über die DMT).', Methods),
    K('abstract', Directive, 'Methode ohne Implementierung; Nachfahren müssen sie überschreiben.', Methods),
    K('final', Directive, 'Methode darf nicht weiter überschrieben, Klasse nicht abgeleitet werden.', Methods),
    K('static', Directive, 'Klassenmethode ohne Self; nicht virtuell.', Methods),
    K('message', Directive, 'Message-Handler: Methode wird für die angegebene Windows-Nachricht aufgerufen.',
      Methods + '#Message_Methods'),
    K('inline', Reserved, 'Bittet den Compiler, die Routine an der Aufrufstelle einzusetzen.',
      'Calling_Procedures_and_Functions_(Delphi)#Using_the_inline_Directive'),
    K('forward', Directive, 'Vorwärtsdeklaration einer Routine, deren Rumpf später folgt.',
      Routines + '#Forward_and_Interface_Declarations'),
    K('external', Directive, 'Routine aus einer DLL oder Objektdatei.', Routines + '#External_Declarations'),
    K('assembler', Directive, 'Routine in Assembler (veraltet, nur zur Kompatibilität).', 'Inline_Assembly_Code'),
    K('varargs', Directive, 'Variable Parameterliste für externe C-Routinen.', Routines + '#Varargs'),
    K('noreturn', Directive, 'Routine kehrt nicht zurück (z. B. nach raise).', Routines),
    K('delayed', Directive, 'DLL wird erst beim ersten Aufruf geladen.', 'Libraries_and_Packages_(Delphi)'),
    K('cdecl', Directive, 'Aufrufkonvention von C: Parameter von rechts nach links, Aufrufer räumt den Stack.',
      Routines + '#Calling_Conventions'),
    K('stdcall', Directive, 'Aufrufkonvention der Windows-API.', Routines + '#Calling_Conventions'),
    K('safecall', Directive, 'Aufrufkonvention für COM: Ausnahmen werden zu HResult.',
      Routines + '#Calling_Conventions'),
    K('register', Directive, 'Standard-Aufrufkonvention von Delphi (Parameter in Registern).',
      Routines + '#Calling_Conventions'),
    K('pascal', Directive, 'Ältere Aufrufkonvention: Parameter von links nach rechts.',
      Routines + '#Calling_Conventions'),
    K('winapi', Directive, 'Aufrufkonvention der Plattform-API (stdcall unter Windows).',
      Routines + '#Calling_Conventions'),
    K('dispid', Directive, 'Nummer eines Mitglieds in einer Dispatch-Schnittstelle (Automation).',
      'Automation_Objects_(Delphi)'),
    // Hinweisdirektiven
    K('deprecated', Directive, 'Verwendung erzeugt eine Warnung; optional mit Hinweistext.', Hints),
    K('platform', Directive, 'Nur auf bestimmten Plattformen verfügbar; Verwendung erzeugt eine Warnung.', Hints),
    K('experimental', Directive, 'Noch nicht stabil; Verwendung erzeugt eine Warnung.', Hints),
    K('library', Reserved, 'Kopf eines DLL-Projekts; als Hinweisdirektive: nur in dieser Bibliothek.', Hints),
    // Sichtbarkeit und Klassen
    K('strict private', 'Sichtbarkeit', 'Nur innerhalb der Klasse sichtbar, auch nicht für andere Klassen ' +
      'derselben Unit.', Classes + '#Strict_Visibility_Specifiers'),
    K('strict protected', 'Sichtbarkeit', 'Nur in der Klasse und ihren Nachfahren sichtbar, nicht für andere ' +
      'Klassen derselben Unit.', Classes + '#Strict_Visibility_Specifiers'),
    K('protected', 'Sichtbarkeit', 'Sichtbar in der Klasse, ihren Nachfahren und der eigenen Unit.', Classes),
    K('public', 'Sichtbarkeit', 'Überall sichtbar.', Classes),
    K('published', 'Sichtbarkeit', 'Überall sichtbar, mit RTTI für den Objektinspektor und das Streaming (.dfm).',
      Classes + '#Published_Members'),
    K('automated', 'Sichtbarkeit', 'Veraltet: wie public, mit Automation-Typinformationen.', Classes),
    K('class var', 'Deklaration', 'Klassenfeld: ein Wert für alle Instanzen der Klasse.',
      'Fields_(Delphi)#Class_Fields'),
    K('sealed', Directive, 'Von der Klasse darf nicht abgeleitet werden.', Classes),
    K('helper', Directive, 'Class Helper bzw. Record Helper: erweitert einen Typ um Methoden.',
      'Class_and_Record_Helpers_(Delphi)'),
    K('dispinterface', Reserved, 'Dispatch-Schnittstelle für Automation (Aufruf über IDispatch).',
      'Automation_Objects_(Delphi)#Dispatch_Interface_Types'),
    K('object', Reserved, 'Veralteter Objekttyp (Turbo Pascal); heute class bzw. record verwenden.',
      'Classes_and_Objects_(Delphi)#Object_Types'),
    K('packed', Reserved, 'Felder ohne Ausrichtungslücken ablegen.',
      'Structured_Types_(Delphi)#Alignment_of_Structured_Types'),
    // Properties
    K('property', Reserved, 'Eigenschaft mit Lese- und Schreibzugriff über Felder oder Methoden.', Properties),
    K('implements', Directive, 'Delegiert die Implementierung einer Schnittstelle an eine Property.',
      'Using_Implements_for_Delegation'),
    K('stored', Directive, 'Ob der Wert der Property in der .dfm gespeichert wird (Boolean oder Funktion).',
      Properties + '#Storage_Specifiers'),
    K('default', Directive, 'Standardwert einer Property (wird dann nicht gespeichert) bzw. Standard-Array-Property.',
      Properties + '#Storage_Specifiers'),
    K('nodefault', Directive, 'Hebt einen geerbten Standardwert einer Property auf.',
      Properties + '#Storage_Specifiers'),
    K('index', Directive, 'Index, den mehrere Properties an dieselbe Zugriffsmethode übergeben.',
      Properties + '#Index_Specifiers'),
    K('readonly', Directive, 'Dispatch-Property nur lesbar.', 'Automation_Objects_(Delphi)'),
    K('writeonly', Directive, 'Dispatch-Property nur schreibbar.', 'Automation_Objects_(Delphi)'),
    // Variablen und Anweisungen
    K('absolute', Directive, 'Variable liegt an derselben Adresse wie eine andere Variable.',
      'Variables_(Delphi)#Absolute_Addresses'),
    K('threadvar', Reserved, 'Globale Variable mit eigenem Wert je Thread.',
      'Variables_(Delphi)#Thread-local_Variables'),
    K('resourcestring', Reserved, 'Übersetzbarer String, der als Ressource abgelegt wird.',
      'Resource_Strings_(Delphi)'),
    K('out', Directive, 'Ausgabeparameter: Der Eingangswert wird verworfen.', 'Parameters_(Delphi)#Out_Parameters'),
    K('with', Reserved, 'Macht die Mitglieder eines Objekts ohne Präfix zugänglich; erschwert das Lesen.',
      'Declarations_and_Statements_(Delphi)#With_Statements'),
    K('goto', Reserved, 'Sprung zu einer Marke (label).', 'Declarations_and_Statements_(Delphi)#Goto_Statements'),
    K('label', Reserved, 'Deklariert Sprungmarken für goto.', 'Declarations_and_Statements_(Delphi)#Goto_Statements'),
    K('inherited', Reserved, 'Ruft die gleichnamige Methode des Vorfahren auf.', Methods + '#Inherited'),
    K('asm', Reserved, 'Block mit Inline-Assembler.', 'Inline_Assembly_Code'),
    K('exports', Reserved, 'Routinen, die eine DLL nach außen anbietet.', 'Writing_Dynamically_Loaded_Libraries'),
    K('file', Reserved, 'Dateityp (file of …) für typisierte und untypisierte Dateien.', 'File_Types_(Delphi)'),
    K('initialization', Reserved, 'Code, der beim Laden der Unit ausgeführt wird.',
      'Programs_and_Units_(Delphi)#The_Initialization_Section'),
    K('finalization', Reserved, 'Code, der beim Entladen der Unit ausgeführt wird.',
      'Programs_and_Units_(Delphi)#The_Finalization_Section'),
    K('constructor', Reserved, 'Methode, die eine Instanz anlegt und initialisiert.', Methods + '#Constructors'),
    K('destructor', Reserved, 'Methode, die eine Instanz freigibt; Destroy wird über Free aufgerufen.',
      Methods + '#Destructors'),
    K('shl', Reserved, 'Bits nach links schieben.', Expressions + '#Bitwise_Operators'),
    K('shr', Reserved, 'Bits nach rechts schieben.', Expressions + '#Bitwise_Operators'),
    K('operator', Directive, 'Überladener Operator eines Records (class operator).',
      'Operator_Overloading_(Delphi)'),
    // Delphi 13
    K('if expression', 'Ausdruck', 'Bedingungsausdruck: X := if A then B else C.', Expressions, Delphi13),
    K('is not', 'Operator', 'Negierter Typtest: X is not TFoo.', Expressions, Delphi13),
    K('not in', 'Operator', 'Negierter Mengentest: X not in [A, B].', Expressions, Delphi13)];
end;

{ TKeywordReference }

class function TKeywordReference.All: TArray<TKeywordInfo>;
begin
  Result := Keywords;
end;

class function TKeywordReference.Find(const AName: string; out AInfo: TKeywordInfo): Boolean;
var
  Info: TKeywordInfo;
begin
  for Info in Keywords do
    if SameText(Info.Name, AName) then
    begin
      AInfo := Info;
      Exit(True);
    end;
  Result := False;
end;

function VersionLabel(const AVersion: string): string;
begin
  if AVersion = Delphi13 then
    Result := 'Delphi 13'
  else
    Result := 'BDS ' + AVersion;
end;

class function TKeywordReference.Describe(const AInfo: TKeywordInfo; const ADelphiVersion: string): string;
var
  Title: string;
begin
  if AInfo.Name = 'if expression' then
    Title := 'if … then … else'
  else
    Title := AInfo.Name;
  Result := '**' + Title + '** (' + AInfo.Kind + ')' + #10#10 + AInfo.Text;
  if AInfo.MinVersion <> '' then
  begin
    Result := Result + #10#10 + 'Ab ' + VersionLabel(AInfo.MinVersion) + '.';
    if (TLanguageFeatures.ParseVersion(ADelphiVersion) > 0) and
      (TLanguageFeatures.ParseVersion(ADelphiVersion) < TLanguageFeatures.ParseVersion(AInfo.MinVersion)) then
      Result := Result + ' In diesem Projekt (BDS ' + ADelphiVersion + ') nicht verfügbar.';
  end;
  Result := Result + #10#10 + '[DocWiki](' + TCompilerDirectives.Url(ADelphiVersion, AInfo.Topic) + ')';
end;

function Contains(const ATokenStart, ATokenEnd, APosition: TTextPosition): Boolean;
begin
  Result := ((ATokenStart.Line < APosition.Line) or ((ATokenStart.Line = APosition.Line) and
    (ATokenStart.Character <= APosition.Character))) and ((ATokenEnd.Line > APosition.Line) or
    ((ATokenEnd.Line = APosition.Line) and (ATokenEnd.Character >= APosition.Character)));
end;

/// <summary>Nächstes bzw. vorheriges Token ohne Kommentare; -1 ohne.</summary>
function Neighbour(const ATokens: TArray<TPascalToken>; AIndex, AStep: Integer): Integer;
begin
  Result := AIndex + AStep;
  while (Result >= 0) and (Result <= High(ATokens)) and
    (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Result, AStep);
  if (Result < 0) or (Result > High(ATokens)) then
    Result := -1;
end;

function WordOf(const ATokens: TArray<TPascalToken>; AIndex: Integer): string;
begin
  if (AIndex < 0) or not (ATokens[AIndex].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) then
    Result := ''
  else
    Result := LowerCase(ATokens[AIndex].Text);
end;

class function TKeywordReference.HoverAt(const AText: string; const APosition: TTextPosition;
  const ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Hit, Prev, Next: Integer;
  Word, PrevWord, NextWord, Name: string;
  Info: TKeywordInfo;
begin
  AMarkdown := '';
  Tokens := TPascalLexer.Tokenize(AText);
  Hit := -1;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
      Contains(Tokens[Index].StartPos, Tokens[Index].EndPos, APosition) then
    begin
      Hit := Index;
      Break;
    end;
  if Hit < 0 then
    Exit(False);
  Word := WordOf(Tokens, Hit);
  Prev := Neighbour(Tokens, Hit, -1);
  Next := Neighbour(Tokens, Hit, 1);
  PrevWord := WordOf(Tokens, Prev);
  NextWord := WordOf(Tokens, Next);
  Name := Word;
  if (Word = 'strict') and MatchStr(NextWord, ['private', 'protected']) then
    Name := 'strict ' + NextWord
  else if (PrevWord = 'strict') and MatchStr(Word, ['private', 'protected']) then
    Name := 'strict ' + Word
  else if (Word = 'class') and (NextWord = 'var') then
    Name := 'class var'
  else if (PrevWord = 'class') and (Word = 'var') then
    Name := 'class var'
  else if ((Word = 'is') and (NextWord = 'not')) or ((PrevWord = 'is') and (Word = 'not')) then
    Name := 'is not'
  else if ((Word = 'not') and (NextWord = 'in')) or ((PrevWord = 'not') and (Word = 'in')) then
    Name := 'not in'
  else if (Word = 'if') and (Prev >= 0) and (Tokens[Prev].Kind = TPascalTokenKind.Symbol) and
    (Tokens[Prev].Text <> ';') then
    // Hinter :=, (, , usw. ist if ein Ausdruck, keine Anweisung.
    Name := 'if expression'
  else if MatchText(Word, CommonWords) then
    Exit(False);
  Result := Find(Name, Info);
  if Result then
    AMarkdown := Describe(Info, ADelphiVersion);
end;

initialization
  InitKeywords;

end.
