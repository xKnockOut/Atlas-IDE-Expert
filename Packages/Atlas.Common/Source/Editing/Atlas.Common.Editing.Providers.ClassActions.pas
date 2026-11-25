unit Atlas.Common.Editing.Providers.ClassActions;

// IEditingClassActions über TClassActions: rechnet die Anfrage in den Kontext der Klassen-Aktionen um.

interface

uses
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Editing.Contract.ClassActions;

type
  TEditingClassActionsProvider = class(TInterfacedObject, IEditingClassActions)
  public
    function OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
      out AAction: TCodeAction): Boolean;
    function ImplementInterface(const ARequest: TClassEditRequest; const AInterface: string;
      out AAction: TCodeAction): Boolean;
    function CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
      out AAction: TCodeAction): Boolean;
    class function New: IEditingClassActions; static;
  end;

implementation

uses
  Atlas.Common.Editing.ClassActions;

function ContextOf(const ARequest: TClassEditRequest): TClassActionContext;
begin
  Result := TClassActionContext.Default;
  Result.Index := ARequest.Index;
  Result.Namespaces := ARequest.Namespaces;
  Result.DelphiVersion := ARequest.DelphiVersion;
  Result.Style := ARequest.Style;
end;

{ TEditingClassActionsProvider }

function TEditingClassActionsProvider.OverrideMethod(const ARequest: TClassEditRequest; const AName: string;
  out AAction: TCodeAction): Boolean;
begin
  Result := TClassActions.OverrideMethod(ARequest.Text, ARequest.Line, AName, ContextOf(ARequest), AAction);
end;

function TEditingClassActionsProvider.ImplementInterface(const ARequest: TClassEditRequest;
  const AInterface: string; out AAction: TCodeAction): Boolean;
begin
  Result := TClassActions.ImplementInterface(ARequest.Text, ARequest.Line, AInterface, ContextOf(ARequest),
    AAction);
end;

function TEditingClassActionsProvider.CreateAccessor(const ARequest: TClassEditRequest; const APlan: TAccessorPlan;
  out AAction: TCodeAction): Boolean;
begin
  Result := TClassActions.CreateAccessor(ARequest.Text, ARequest.Line, APlan, ContextOf(ARequest), AAction);
end;

class function TEditingClassActionsProvider.New: IEditingClassActions;
begin
  Result := TEditingClassActionsProvider.Create;
end;

end.
