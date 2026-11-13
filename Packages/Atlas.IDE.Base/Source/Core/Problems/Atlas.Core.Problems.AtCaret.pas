unit Atlas.Core.Problems.AtCaret;

// Atlas-Befund unter der Schreibmarke des oberen Editors (#1886, F1 im Editor), ohne IDE prüfbar (#1967):
// Regel aus demselben Speicher wie Wellenlinien und Hover. Meldungen des Compilers zählen nicht, sie haben
// keine Regelseite; Befunde ohne Code ebenso wenig. Die IDE liefert nur die Schreibmarke über
// IAtlasActiveEditor (Atlas.IDE.Problems.Caret).

interface

uses
  Atlas.Core.Files.Contract,
  Atlas.Core.Problems.Store;

type
  TAtlasProblemAtCaret = class
  public
    /// <summary>Regel des ersten Atlas-Befunds an der Schreibmarke von AEditor in AStore; False ohne Editor,
    /// ohne Speicher oder ohne passenden Befund.</summary>
    class function Rule(const AEditor: IAtlasActiveEditor; AStore: TAtlasProblemStore;
      out ARule: string): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Lsp.Contract;

class function TAtlasProblemAtCaret.Rule(const AEditor: IAtlasActiveEditor; AStore: TAtlasProblemStore;
  out ARule: string): Boolean;
var
  mCaret: TAtlasActiveEditorPos;
  mProblem: TAtlasProblem;
begin
  Result := False;
  ARule := '';
  if (AEditor = nil) or (AStore = nil) then
  begin
    Exit;
  end;
  mCaret := AEditor.Caret;
  if not mCaret.Present then
  begin
    Exit;
  end;
  for mProblem in AStore.At(mCaret.FileName, mCaret.Line, mCaret.Character) do
  begin
    if (mProblem.Source <> TAtlasProblem.cCompilerSource) and (mProblem.Code <> '') then
    begin
      ARule := mProblem.Code;
      Exit(True);
    end;
  end;
end;

end.
