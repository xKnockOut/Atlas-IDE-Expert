unit Shell.Composition.CodeActions.Tests;

// Code-Aktionen der Komposition: das uses-Umfeld kommt aus dem Arbeitsbereich der Datei, ohne Arbeitsbereich
// bleibt es leer, Wissen des Index hängt immer daran.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.CodeActions;

type
  [TestFixture]
  TShellCodeActionsTests = class
  private
    FFound: Boolean;
    FAskedUri: string;
    function WorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
    function NewServices: TShellCodeActionServices;
  public
    [TearDown]
    procedure TearDown;
    /// <summary>usesKeep und Namensräume stammen aus dem Arbeitsbereich der gefragten Datei.</summary>
    [Test]
    procedure UsesContextFromWorkspace;
    /// <summary>Ohne Arbeitsbereich bleibt das Umfeld leer, Index-Abfragen sind trotzdem gesetzt.</summary>
    [Test]
    procedure UsesContextWithoutWorkspace;
  end;

implementation

uses
  Atlas.Common.Editing.Contract;

procedure TShellCodeActionsTests.TearDown;
begin
  FAskedUri := '';
end;

function TShellCodeActionsTests.WorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
begin
  FAskedUri := AUri;
  Result := Default(TShellCodeActionWorkspace);
  Result.Found := FFound;
  if FFound then
  begin
    Result.UsesKeep := TArray<string>.Create('Vcl.Forms');
    Result.Namespaces := TArray<string>.Create('System', 'Vcl');
  end;
end;

function TShellCodeActionsTests.NewServices: TShellCodeActionServices;
begin
  Result := Default(TShellCodeActionServices);
  Result.WorkspaceOf := WorkspaceOf;
end;

procedure TShellCodeActionsTests.UsesContextFromWorkspace;
var
  mCodeActions: TShellCodeActions;
  mContext: TUsesContext;
begin
  FFound := True;
  mCodeActions := TShellCodeActions.Create(NewServices);
  try
    Assert.IsTrue(mCodeActions.UsesContextOf('file:///tmp/A.pas', mContext));
    Assert.AreEqual('file:///tmp/A.pas', FAskedUri);
    Assert.AreEqual(1, Integer(Length(mContext.Keep)));
    Assert.AreEqual('Vcl.Forms', mContext.Keep[0]);
    Assert.AreEqual(2, Integer(Length(mContext.Namespaces)));
    Assert.IsTrue(Assigned(mContext.Info));
    Assert.IsTrue(Assigned(mContext.Declaring));
  finally
    mCodeActions.Free;
  end;
end;

procedure TShellCodeActionsTests.UsesContextWithoutWorkspace;
var
  mCodeActions: TShellCodeActions;
  mContext: TUsesContext;
begin
  FFound := False;
  mCodeActions := TShellCodeActions.Create(NewServices);
  try
    Assert.IsTrue(mCodeActions.UsesContextOf('file:///tmp/B.pas', mContext));
    Assert.AreEqual(0, Integer(Length(mContext.Keep)));
    Assert.AreEqual(0, Integer(Length(mContext.Namespaces)));
    Assert.IsTrue(Assigned(mContext.Info));
  finally
    mCodeActions.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCodeActionsTests);

end.
