unit Atlas.Common.Editing.Contract.ClassCompletion;

// Klassenvervollständigung (#42, #124, #996), die Editing anderen Features anbietet (API): Deklarationen und
// Rümpfe einer Unit einander zuordnen, Paare mit abweichendem Kopf, fehlende Rümpfe anlegen, fehlende
// Deklarationen ergänzen, Köpfe angleichen. Abnehmer sind die Prüfregeln zu Deklarationen über den Host-Adapter
// Adapters.Checks.Refactorings; erzeugt in Atlas.Common.Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.CodeActions.Contract;

type
  /// <summary>Methode ohne Gegenstück (#124).</summary>
  TEditingUnmatchedMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>True: deklariert, aber ohne Rumpf; False: Rumpf ohne Deklaration.</summary>
    Declared: Boolean;
    /// <summary>Kopf ohne ";", z. B. "procedure TFoo.Bar(A: Integer)" beim Rumpf.</summary>
    Header: string;
  end;

  /// <summary>Ein Parameter eines Methodenkopfs (#996).</summary>
  TEditingShapeParameter = record
    /// <summary>const, var, out, constref oder '' (Kleinbuchstaben).</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeName: string;
  end;

  /// <summary>Zerlegter Kopf einer Methode (#996).</summary>
  TEditingSignatureShape = record
    /// <summary>procedure, function, constructor, destructor oder operator.</summary>
    Kind: string;
    Parameters: TArray<TEditingShapeParameter>;
    /// <summary>Ergebnistyp wie geschrieben; '' ohne.</summary>
    ResultType: string;
    /// <summary>Aufrufkonvention in Kleinbuchstaben (stdcall, cdecl …); '' ohne Angabe.</summary>
    Convention: string;
    ConventionRange: TTextRange;
    /// <summary>Im Kopf steht bedingte Übersetzung ({$IFDEF} …); welche Parameter gelten, ist offen (#1324).
    /// </summary>
    Conditional: Boolean;
  end;

  /// <summary>Deklaration und Rumpf gleichen Namens, deren Köpfe voneinander abweichen (#996).</summary>
  TEditingSignaturePair = record
    Declaration: TEditingUnmatchedMethod;
    Body: TEditingUnmatchedMethod;
    DeclarationShape: TEditingSignatureShape;
    BodyShape: TEditingSignatureShape;
  end;

  /// <summary>Zuordnung einer Unit; gilt, solange der Baum hinter dem Handle lebt.</summary>
  IEditingClassCompletionScan = interface
    ['{A8C789F6-EEEB-4245-9C02-5F1752F1F6FE}']
    /// <summary>Deklarierte Methoden ohne Rumpf und Rümpfe ohne Deklaration.</summary>
    function Unmatched: TArray<TEditingUnmatchedMethod>;
    /// <summary>Deklaration und Rumpf gleichen Namens mit abweichendem Kopf.</summary>
    function Pairs: TArray<TEditingSignaturePair>;
    /// <summary>Gehört AMethod zu einem der Paare?</summary>
    function InPair(const AMethod: TEditingUnmatchedMethod): Boolean;
    /// <summary>Zerlegter Kopf der Methode ASymbol; False, wenn er sich nicht lesen lässt.</summary>
    function Shape(const ASymbol: TIndexSymbol; out AShape: TEditingSignatureShape): Boolean;
    /// <summary>Leere Rümpfe für die fehlenden Methoden an APosition (eine Methode oder der Typ dort).</summary>
    function MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
    /// <summary>Fehlende Deklaration für den Rumpf AMethod im private-Abschnitt seines Typs.</summary>
    function AddDeclaration(const AMethod: TEditingUnmatchedMethod; out AEdit: TTextEdit): Boolean;
    /// <summary>Rumpf und Deklaration von APair in beide Richtungen angleichen.</summary>
    function PairFixes(const APair: TEditingSignaturePair; out AFixes: TArray<TCodeAction>): Boolean;
  end;

  /// <summary>Erzeugt die Zuordnung einer Unit.</summary>
  IEditingClassCompletion = interface
    ['{6AB5F5CA-2725-48EF-B87F-93FB552FD178}']
    /// <summary>Zuordnung für AText mit dem Baum ATree und seinem Index AUnit; neue Rümpfe nach ASettings und
    /// AStyle. Ohne Baum nil.</summary>
    function Scan(const AText: string; const ATree: IPascalSyntaxTree; const AUnit: TUnitIndex;
      const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle): IEditingClassCompletionScan;
  end;

implementation

end.
