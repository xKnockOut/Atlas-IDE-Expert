unit Atlas.Common.Rules.Contract.Refactorings;

// Was Prüfregeln von Refactorings brauchen, um eine Korrektur anzubieten (SPI des Features Rules). Rules kennt
// die Refactorings nicht; der Host gibt sie über Adapter in TRuleServices.Refactorings. Ein nil-Eintrag heißt:
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
  IRuleClassRefactorings = interface
    ['{B7324D9A-6165-4B5F-871F-C9883D6E647B}']
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
  end;

  /// <summary>„Konstante extrahieren“ für viele Literale desselben Textes.</summary>
  IRuleConstantExtraction = interface
    ['{413771C5-D0DB-4B00-AA72-7A50F25B7310}']
    /// <summary>Konstante für das Literal in ARange; False, wenn dort keins steht.</summary>
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

  /// <summary>Extrahieren als Korrektur: Bedingung in Funktion auslagern, Konstante einführen.</summary>
  IRuleExtractRefactorings = interface
    ['{70350A32-331D-4BB4-85DC-954DCCABFBE2}']
    /// <summary>„Bedingung in Funktion auslagern“ für die ganze Bedingung in ARange; False, wenn es nicht geht.
    /// </summary>
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    /// <summary>„Konstante extrahieren“ für AText mit dem Baum ATree der Regel; neue Namen mit den Präfixen ANames.
    /// Gilt, solange der Baum hinter ATree lebt; nil ohne Baum.</summary>
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
  end;

  /// <summary>Was die Suche nach Methoden ohne Self über eine Unit wissen muss.</summary>
  TRuleMethodScan = record
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
  TRuleMethodWithoutSelf = record
    ClassName: string;
    Name: string;
    /// <summary>Name im Kopf der Implementierung.</summary>
    NamePosition: TTextPosition;
    /// <summary>Umwandlung in eine class-Methode, nur in dieser Unit; ohne HasFix nicht möglich.</summary>
    HasFix: Boolean;
    Fix: TCodeAction;
  end;

  /// <summary>Methoden ohne Self samt Korrektur „In class-Methode umwandeln“.</summary>
  IRuleMethodRefactorings = interface
    ['{49CD21CC-66DB-477C-9138-3E794F2B58A8}']
    function WithoutSelf(const AScan: TRuleMethodScan): TArray<TRuleMethodWithoutSelf>;
  end;

  /// <summary>Alle Refactorings, die Prüfregeln als Korrektur nutzen; je Eintrag nil = nicht verfügbar.</summary>
  TRuleRefactorings = record
    Classes: IRuleClassRefactorings;
    Extract: IRuleExtractRefactorings;
    /// <summary>Ohne Eintrag schweigt method-without-self: Erkennung und Korrektur gehören zusammen.</summary>
    Methods: IRuleMethodRefactorings;
  end;

implementation

end.
