unit Atlas.Core.Designer.TestSupport;

// Gemeinsame Hilfen der Tests der Formularprüfung (Anordnung, Skalierung).

interface

uses
  Atlas.Core.Designer.Layout;

/// <summary>True, wenn AFindings für den Knoten ANode das Problem AProblem enthält; AFinding ist dann der Fund.</summary>
function Has(const AFindings: TArray<TAtlasLayoutFinding>; ANode: Integer; AProblem: TAtlasLayoutProblem;
  out AFinding: TAtlasLayoutFinding): Boolean;

implementation

function Has(const AFindings: TArray<TAtlasLayoutFinding>; ANode: Integer; AProblem: TAtlasLayoutProblem;
  out AFinding: TAtlasLayoutFinding): Boolean;
var
  mFinding: TAtlasLayoutFinding;
begin
  for mFinding in AFindings do
  begin
    if (mFinding.Node = ANode) and (mFinding.Problem = AProblem) then
    begin
      AFinding := mFinding;
      Exit(True);
    end;
  end;
  AFinding := Default(TAtlasLayoutFinding);
  Result := False;
end;

end.
