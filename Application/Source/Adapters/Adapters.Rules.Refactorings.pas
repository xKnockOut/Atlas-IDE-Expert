unit Adapters.Rules.Refactorings;

// Host-Adapter zwischen Rules und Editing: Prüfregeln bieten Korrekturen aus Refactorings über
// TRuleRefactorings an (SPI im Rules-Contract), Editing bietet die Refactorings über seinen Contract an (API).
// Erzeugt nur in Shell.Composition.*; kennt nur die Contracts.

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Rules.Contract.Refactorings,
  Atlas.Common.Editing.Contract.ClassActions;

type
  /// <summary>IRuleClassRefactorings über die Klassen-Aktionen von Editing.</summary>
  TRuleClassRefactoringsAdapter = class(TInterfacedObject, IRuleClassRefactorings)
  private
    FActions: IEditingClassActions;
  public
    constructor Create(const AActions: IEditingClassActions);
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
  end;

  /// <summary>Die Refactorings für die Prüfregeln aus den APIs von Editing.</summary>
  TRuleRefactoringsAdapters = record
    /// <summary>AClasses nil: keine Klassen-Aktionen.</summary>
    class function Create(const AClasses: IEditingClassActions): TRuleRefactorings; static;
  end;

implementation

{ TRuleClassRefactoringsAdapter }

constructor TRuleClassRefactoringsAdapter.Create(const AActions: IEditingClassActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TRuleClassRefactoringsAdapter.OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.OverrideMethod(ARequest, AName, AAction);
end;

function TRuleClassRefactoringsAdapter.ImplementInterface(const ARequest: TClassEditRequest;
  const AInterface: string; out AAction: TCodeAction): Boolean;
begin
  Result := FActions.ImplementInterface(ARequest, AInterface, AAction);
end;

function TRuleClassRefactoringsAdapter.CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.CreateAccessor(ARequest, APlan, AAction);
end;

{ TRuleRefactoringsAdapters }

class function TRuleRefactoringsAdapters.Create(const AClasses: IEditingClassActions): TRuleRefactorings;
begin
  Result := Default(TRuleRefactorings);
  if AClasses <> nil then
  begin
    Result.Classes := TRuleClassRefactoringsAdapter.Create(AClasses);
  end;
end;

end.
