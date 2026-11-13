unit Shell.Composition.Refactorings;

// Internals-Rolle Shell: Fassade der Refactorings des Servers. Legt die Teile an, meldet ihre Befehle an und liefert
// ihre Code-Aktionen in fester Reihenfolge (so stehen sie im Menü des Editors). Auch die Befehle des Debuggers
// (Shell.Composition.Stepping) laufen hierüber, sie brauchen dieselben Dienste.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellRefactorings = class(TShellRefactoringPart)
  private
    FParts: TArray<TShellRefactoringPart>;
  public
    constructor Create(const AServices: TShellRefactoringServices);
    destructor Destroy; override;
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  Shell.Composition.Refactorings.Structure,
  Shell.Composition.Refactorings.Visibility,
  Shell.Composition.Refactorings.Conversions,
  Shell.Composition.Refactorings.Types,
  Shell.Composition.Refactorings.Fixes,
  Shell.Composition.Refactorings.Editing,
  Shell.Composition.Stepping;

constructor TShellRefactorings.Create(const AServices: TShellRefactoringServices);
begin
  inherited Create(AServices);
  FParts := TArray<TShellRefactoringPart>.Create(TShellStructureRefactorings.Create(AServices),
    TShellVisibilityRefactorings.Create(AServices),
    TShellConversionRefactorings.Create(AServices), TShellTypeRefactorings.Create(AServices),
    TShellFixRefactorings.Create(AServices), TShellEditingRefactorings.Create(AServices),
    TShellStepping.Create(AServices));
end;

destructor TShellRefactorings.Destroy;
var
  mPart: TShellRefactoringPart;
begin
  for mPart in FParts do
  begin
    mPart.Free;
  end;
  FParts := nil;
  inherited;
end;

procedure TShellRefactorings.Register(ACommands: TLspCommands);
var
  mPart: TShellRefactoringPart;
begin
  for mPart in FParts do
  begin
    mPart.Register(ACommands);
  end;
end;

function TShellRefactorings.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
var
  mPart: TShellRefactoringPart;
begin
  Result := nil;
  for mPart in FParts do
  begin
    Result := Result + mPart.Actions(AUri, ARange);
  end;
end;

end.
