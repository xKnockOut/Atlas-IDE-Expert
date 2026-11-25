unit Atlas.Common.Checks.Contract.Refactorings;

// Was Prüfregeln von Refactorings brauchen, um eine Korrektur anzubieten (SPI des Features Rules). Rules kennt
// die Refactorings nicht; der Host gibt sie über Adapter in TCheckServices.Refactorings. Ein nil-Eintrag heißt:
// keine solche Korrektur anbieten, der Befund bleibt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract;

type
  /// <summary>Klassen-Aktionen als Korrektur: Methode überschreiben, Interface implementieren, Feld oder
  /// Zugriffsmethode einer Eigenschaft anlegen. Jede liefert False, wenn es dort nichts zu tun gibt.</summary>
  ICheckClassRefactorings = interface
    ['{B7324D9A-6165-4B5F-871F-C9883D6E647B}']
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
  end;

  /// <summary>„Konstante extrahieren“ für viele Literale desselben Textes.</summary>
  ICheckConstantExtraction = interface
    ['{413771C5-D0DB-4B00-AA72-7A50F25B7310}']
    /// <summary>Konstante für das Literal in ARange; False, wenn dort keins steht.</summary>
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

  /// <summary>Extrahieren als Korrektur: Bedingung in Funktion auslagern, Konstante einführen.</summary>
  ICheckExtractRefactorings = interface
    ['{70350A32-331D-4BB4-85DC-954DCCABFBE2}']
    /// <summary>„Bedingung in Funktion auslagern“ für die ganze Bedingung in ARange; False, wenn es nicht geht.
    /// </summary>
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    /// <summary>„Konstante extrahieren“ für AText mit dem Baum ATree der Regel; neue Namen mit den Präfixen ANames.
    /// Gilt, solange der Baum hinter ATree lebt; nil ohne Baum.</summary>
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): ICheckConstantExtraction;
  end;

  /// <summary>Was die Suche nach Methoden ohne Self über eine Unit wissen muss.</summary>
  TCheckMethodScan = record
    /// <summary>Dateiname für die Namensauflösung (TRuleContext.ResolverFileName).</summary>
    FileName: string;
    Text: string;
    /// <summary>Baum der Regel zu Text (aktive Zweige).</summary>
    Tree: IPascalSyntaxTree;
    /// <summary>Inhalt der Formulardatei; '' ohne.</summary>
    FormText: string;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TArray<string>;
    /// <summary>class-Methoden mit static (refactoring.methodKind).</summary>
    WithStatic: Boolean;
    Style: TFormatStyle;
  end;

  /// <summary>Eine Methode, die Self nicht braucht.</summary>
  TCheckMethodWithoutSelf = record
    ClassName: string;
    Name: string;
    /// <summary>Name im Kopf der Implementierung.</summary>
    NamePosition: TTextPosition;
    /// <summary>Umwandlung in eine class-Methode, nur in dieser Unit; ohne HasFix nicht möglich.</summary>
    HasFix: Boolean;
    Fix: TCodeAction;
  end;

  /// <summary>Methoden ohne Self samt Korrektur „In class-Methode umwandeln“.</summary>
  ICheckMethodRefactorings = interface
    ['{49CD21CC-66DB-477C-9138-3E794F2B58A8}']
    function WithoutSelf(const AScan: TCheckMethodScan): TArray<TCheckMethodWithoutSelf>;
  end;

  /// <summary>Wie die Methodenrümpfe geordnet sein sollen (Regel method-order).</summary>
  TCheckMethodOrderRequest = record
    /// <summary>off, declaration, alphabetical, grouped; '' = grouped, Unbekanntes = declaration.</summary>
    Placement: string;
    /// <summary>Lebenszyklus auch bei declaration und alphabetical zuerst.</summary>
    LifecycleFirst: Boolean;
    /// <summary>Leerzeilen an den Grenzen verschobener Rümpfe angleichen.</summary>
    BlankLines: Boolean;
    /// <summary>Form des Typkommentars wie classCompletion.typeComment; off = keinen verlangen, leer = brace.
    /// </summary>
    TypeComment: string;
    /// <summary>Breite der Trennlinie; 0 = Vorgabe.</summary>
    LineLength: Integer;
  end;

  /// <summary>Stand eines Typs: Ordnung der Rümpfe und Typkommentar samt Korrekturen.</summary>
  TCheckMethodTypeReview = record
    TypeName: string;
    /// <summary>Typname im Kopf des ersten Rumpfs.</summary>
    NameRange: TTextRange;
    /// <summary>Ordnet nur die Rümpfe dieses Typs; nil = sie stehen schon in der Ordnung.</summary>
    OrderEdits: TArray<TTextEdit>;
    /// <summary>Fügt den fehlenden Typkommentar ein; nil = vorhanden oder nicht verlangt.</summary>
    CommentEdits: TArray<TTextEdit>;
    /// <summary>Zeile des einzufügenden Kommentars, z. B. "{ TKunde }"; '' ohne.</summary>
    CommentText: string;
  end;

  /// <summary>Ergebnis der Prüfung einer Unit.</summary>
  TCheckMethodOrderReview = record
    /// <summary>Die verstandene Ordnung: off, declaration, alphabetical oder grouped.</summary>
    Placement: string;
    /// <summary>Je Typ mit Rümpfen in der Reihenfolge des ersten Rumpfs; leer bei off.</summary>
    Types: TArray<TCheckMethodTypeReview>;
  end;

  /// <summary>Methodenordnung je Typ samt Korrekturen „Rümpfe ordnen“ und „Typkommentar einfügen“.</summary>
  ICheckMethodOrderRefactorings = interface
    ['{2414CF06-ECF0-4E37-B679-E9806D2A3B1A}']
    /// <summary>ATree ist der Baum der Regel zu AText.</summary>
    function Review(const AText: string; const ATree: IPascalSyntaxTree;
      const ARequest: TCheckMethodOrderRequest): TCheckMethodOrderReview;
  end;

  /// <summary>Methode ohne Gegenstück: deklariert ohne Rumpf oder Rumpf ohne Deklaration.</summary>
  TCheckUnmatchedMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>True: deklariert, aber ohne Rumpf; False: Rumpf ohne Deklaration.</summary>
    Declared: Boolean;
    /// <summary>Kopf ohne ";", z. B. "procedure TFoo.Bar(A: Integer)" beim Rumpf.</summary>
    Header: string;
  end;

  /// <summary>Ein Parameter eines Methodenkopfs.</summary>
  TCheckShapeParameter = record
    /// <summary>const, var, out, constref oder '' (Kleinbuchstaben).</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeName: string;
  end;

  /// <summary>Zerlegter Kopf einer Methode.</summary>
  TCheckSignatureShape = record
    /// <summary>procedure, function, constructor, destructor oder operator.</summary>
    Kind: string;
    Parameters: TArray<TCheckShapeParameter>;
    /// <summary>Ergebnistyp wie geschrieben; '' ohne.</summary>
    ResultType: string;
    /// <summary>Aufrufkonvention in Kleinbuchstaben (stdcall, cdecl …); '' ohne Angabe.</summary>
    Convention: string;
    ConventionRange: TTextRange;
    /// <summary>Im Kopf steht bedingte Übersetzung ({$IFDEF} …); welche Parameter gelten, ist offen.</summary>
    Conditional: Boolean;
  end;

  /// <summary>Deklaration und Rumpf gleichen Namens, deren Köpfe voneinander abweichen.</summary>
  TCheckSignaturePair = record
    Declaration: TCheckUnmatchedMethod;
    Body: TCheckUnmatchedMethod;
    DeclarationShape: TCheckSignatureShape;
    BodyShape: TCheckSignatureShape;
  end;

  /// <summary>Zuordnung von Deklarationen und Rümpfen einer Unit samt Korrekturen; gilt, solange der Baum der
  /// Regel lebt.</summary>
  ICheckClassCompletionScan = interface
    ['{C6B1F526-0F6F-4DF6-8C8C-77173F34C13F}']
    /// <summary>Deklarierte Methoden ohne Rumpf und Rümpfe ohne Deklaration.</summary>
    function Unmatched: TArray<TCheckUnmatchedMethod>;
    /// <summary>Deklaration und Rumpf gleichen Namens mit abweichendem Kopf.</summary>
    function Pairs: TArray<TCheckSignaturePair>;
    /// <summary>Gehört AMethod zu einem der Paare?</summary>
    function InPair(const AMethod: TCheckUnmatchedMethod): Boolean;
    /// <summary>Zerlegter Kopf der Methode ASymbol; False, wenn er sich nicht lesen lässt.</summary>
    function Shape(const ASymbol: TIndexSymbol; out AShape: TCheckSignatureShape): Boolean;
    /// <summary>Leere Rümpfe für die fehlenden Methoden an APosition.</summary>
    function MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
    /// <summary>Fehlende Deklaration für den Rumpf AMethod.</summary>
    function AddDeclaration(const AMethod: TCheckUnmatchedMethod; out AEdit: TTextEdit): Boolean;
    /// <summary>Rumpf und Deklaration von APair in beide Richtungen angleichen.</summary>
    function PairFixes(const APair: TCheckSignaturePair; out AFixes: TArray<TCodeAction>): Boolean;
  end;

  /// <summary>Klassenvervollständigung für die Regeln zu Deklarationen.</summary>
  ICheckClassCompletionRefactorings = interface
    ['{7EA15822-8169-488E-ADEB-CE6B0DF8E596}']
    /// <summary>Zuordnung für AText mit dem Baum ATree der Regel und seinem Index AUnit; neue Rümpfe nach
    /// ASettings und AStyle. Ohne Baum nil.</summary>
    function Scan(const AText: string; const ATree: IPascalSyntaxTree; const AUnit: TUnitIndex;
      const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle): ICheckClassCompletionScan;
  end;

  /// <summary>Befehlszeile "/name", die stehen bleibt, samt Grund.</summary>
  TCheckSlashProblem = record
    Range: TTextRange;
    Message: string;
  end;

  /// <summary>Schnellbefehle von Editing: welche Befehlszeilen nicht ausgeführt würden (Regel slash-command).
  /// </summary>
  ICheckSlashCommands = interface
    ['{A724AD51-3173-4798-A78E-5E96B33CD2C5}']
    /// <summary>Befehlszeilen in AText, die stehen blieben, samt Grund. AIndex darf nil sein.</summary>
    function Problems(const AText: string; const AIndex: ISymbolIndex;
      const ADelphiVersion: string): TArray<TCheckSlashProblem>;
    /// <summary>Hinweis zu "/ignore ARuleId", wenn die Regel in der Zeile darunter nichts meldet.</summary>
    function IgnoreWithoutHit(const ARuleId: string): string;
  end;

  /// <summary>Alle Refactorings, die Prüfregeln als Korrektur nutzen; je Eintrag nil = nicht verfügbar.</summary>
  TCheckRefactorings = record
    Classes: ICheckClassRefactorings;
    Extract: ICheckExtractRefactorings;
    /// <summary>Ohne Eintrag schweigt method-without-self: Erkennung und Korrektur gehören zusammen.</summary>
    Methods: ICheckMethodRefactorings;
    /// <summary>Ohne Eintrag schweigt method-order.</summary>
    Order: ICheckMethodOrderRefactorings;
    /// <summary>Ohne Eintrag schweigen declared-not-implemented, implemented-not-declared und signature-mismatch.
    /// </summary>
    Completion: ICheckClassCompletionRefactorings;
    /// <summary>Ohne Eintrag schweigt slash-command.</summary>
    Commands: ICheckSlashCommands;
  end;

implementation

end.
