unit Editing.Contract.ClassCompletion;

// Klassenvervollständigung (#42, #124, #996), die Editing anderen Features anbietet (API): Deklarationen und
// Rümpfe einer Unit einander zuordnen, Paare mit abweichendem Kopf, fehlende Rümpfe anlegen, fehlende
// Deklarationen ergänzen, Köpfe angleichen. Abnehmer sind die Prüfregeln zu Deklarationen über den Host-Adapter
// Adapters.Checks.Refactorings; erzeugt in Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Semantics.Contract;

type
  /// <summary>Zuordnung einer Unit; gilt, solange der Baum hinter dem Handle lebt.</summary>
  IEditingClassCompletionScan = interface
    ['{A8C789F6-EEEB-4245-9C02-5F1752F1F6FE}']
    /// <summary>Deklarierte Methoden ohne Rumpf und Rümpfe ohne Deklaration.</summary>
    function Unmatched: TArray<TUnmatchedMethod>;
    /// <summary>Deklaration und Rumpf gleichen Namens mit abweichendem Kopf.</summary>
    function Pairs: TArray<TSignaturePair>;
    /// <summary>Gehört AMethod zu einem der Paare?</summary>
    function InPair(const AMethod: TUnmatchedMethod): Boolean;
    /// <summary>Zerlegter Kopf der Methode ASymbol; False, wenn er sich nicht lesen lässt.</summary>
    function Shape(const ASymbol: TIndexSymbol; out AShape: TSignatureShape): Boolean;
    /// <summary>Leere Rümpfe für die fehlenden Methoden an APosition (eine Methode oder der Typ dort).</summary>
    function MissingBodies(const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
    /// <summary>Fehlende Deklaration für den Rumpf AMethod im private-Abschnitt seines Typs.</summary>
    function AddDeclaration(const AMethod: TUnmatchedMethod; out AEdit: TTextEdit): Boolean;
    /// <summary>Rumpf und Deklaration von APair in beide Richtungen angleichen.</summary>
    function PairFixes(const APair: TSignaturePair; out AFixes: TArray<TCodeAction>): Boolean;
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
