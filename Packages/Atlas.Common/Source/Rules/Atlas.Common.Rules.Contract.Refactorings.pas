unit Atlas.Common.Rules.Contract.Refactorings;

// Was Prüfregeln von Refactorings brauchen, um eine Korrektur anzubieten (SPI des Features Rules). Rules kennt
// die Refactorings nicht; der Host gibt sie über Adapter in TRuleServices.Refactorings. Ein nil-Eintrag heißt:
// keine solche Korrektur anbieten, der Befund bleibt.

interface

uses
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

  /// <summary>Alle Refactorings, die Prüfregeln als Korrektur nutzen; je Eintrag nil = nicht verfügbar.</summary>
  TRuleRefactorings = record
    Classes: IRuleClassRefactorings;
  end;

implementation

end.
