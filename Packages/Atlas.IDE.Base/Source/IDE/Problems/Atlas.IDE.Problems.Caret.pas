unit Atlas.IDE.Problems.Caret;

// Atlas-Befund unter der Einfügemarke des oberen Editors (#1886, F1 im Editor): Regel aus demselben Speicher wie
// Wellenlinien und Hover (TAtlasProblemsController.Current). Die Entscheidung trifft
// Atlas.Core.Problems.AtCaret (#1967); hier nur der obere Editor und der Speicher. Nur im Hauptthread verwenden.

interface

type
  TAtlasIdeProblemAtCaret = class
  public
    /// <summary>Regel des ersten Atlas-Befunds an der Einfügemarke; False ohne.</summary>
    class function Rule(out ARule: string): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Files.Contract,
  Atlas.Core.Problems.AtCaret,
  Atlas.IDE.Foundation.ActiveEditor,
  Atlas.IDE.Problems.Controller;

class function TAtlasIdeProblemAtCaret.Rule(out ARule: string): Boolean;
var
  mEditor: IAtlasActiveEditor;
begin
  mEditor := TAtlasIdeActiveEditor.Create;
  Result := TAtlasProblemAtCaret.Rule(mEditor, TAtlasProblemsController.Current, ARule);
end;

end.
