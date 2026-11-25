unit Atlas.Common.Rules.Contract.Refactorings;

// Was Prüfregeln von Refactorings brauchen, um eine Korrektur anzubieten (SPI des Features Rules). Rules kennt
// die Refactorings nicht; der Host gibt sie über Adapter in TRuleServices.Refactorings. Ein nil-Eintrag heißt:
// keine solche Korrektur anbieten, der Befund bleibt.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
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
    function ExtractCondition(const AText: string; const ARange: TTextRange; const AStyle: TFormatStyle;
      out AAction: TCodeAction): Boolean;
    /// <summary>„Konstante extrahieren“ für AText; neue Namen mit den Präfixen ANames.</summary>
    function ConstantExtraction(const AText: string; const ANames: TPascalNamePrefixes): IRuleConstantExtraction;
  end;

  /// <summary>Alle Refactorings, die Prüfregeln als Korrektur nutzen; je Eintrag nil = nicht verfügbar.</summary>
  TRuleRefactorings = record
    Classes: IRuleClassRefactorings;
    Extract: IRuleExtractRefactorings;
  end;

implementation

end.
