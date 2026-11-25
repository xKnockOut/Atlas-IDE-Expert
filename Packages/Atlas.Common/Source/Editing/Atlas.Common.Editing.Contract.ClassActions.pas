unit Atlas.Common.Editing.Contract.ClassActions;

// Klassen-Aktionen, die Editing anderen Features anbietet (API): Methode überschreiben, Interface
// implementieren, Feld oder Zugriffsmethode einer Eigenschaft anlegen. Erzeugt wird die Umsetzung
// (Editing.Providers.ClassActions) von der Zusammensetzung des Hosts; Abnehmer erreichen sie über Host-Adapter.

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract;

type
  /// <summary>Klassen-Aktionen; jede liefert False, wenn es an der Stelle nichts zu tun gibt.</summary>
  IEditingClassActions = interface
    ['{7167A785-6DD6-49B4-8C32-6BAA3F12A218}']
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
  end;

implementation

end.
