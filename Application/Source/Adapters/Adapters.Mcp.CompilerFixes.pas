unit Adapters.Mcp.CompilerFixes;

// Host-Adapter zwischen Mcp und Editing: explain_compiler_message holt Korrekturen über IMcpCompilerFixes, Editing
// bietet sie über IEditingCompilerFixes an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Mcp.Contract.CompilerFixes,
  Editing.Contract.CompilerFixes;

type
  TMcpCompilerFixesAdapter = class(TInterfacedObject, IMcpCompilerFixes)
  private
    FFixes: IEditingCompilerFixes;
  public
    constructor Create(const AFixes: IEditingCompilerFixes);
    function Fixes(const AText: string; const AMessage: TMcpFixMessage): TArray<TMcpCompilerFix>;
  end;

implementation

{ TMcpCompilerFixesAdapter }

constructor TMcpCompilerFixesAdapter.Create(const AFixes: IEditingCompilerFixes);
begin
  inherited Create;
  FFixes := AFixes;
end;

function TMcpCompilerFixesAdapter.Fixes(const AText: string; const AMessage: TMcpFixMessage): TArray<TMcpCompilerFix>;
var
  mFixes: TArray<TCompilerFix>;
  mIndex: Integer;
begin
  mFixes := FFixes.Fixes(AText, TFixMessage.Create(AMessage.Code, AMessage.Line, AMessage.Column, AMessage.Text));
  Result := nil;
  SetLength(Result, Length(mFixes));
  for mIndex := 0 to High(mFixes) do
  begin
    Result[mIndex].Title := mFixes[mIndex].Title;
    Result[mIndex].Edits := mFixes[mIndex].Edits;
    Result[mIndex].Preferred := mFixes[mIndex].Preferred;
  end;
end;

end.
