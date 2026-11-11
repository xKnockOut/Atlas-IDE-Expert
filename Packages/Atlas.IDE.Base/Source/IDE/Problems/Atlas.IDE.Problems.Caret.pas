unit Atlas.IDE.Problems.Caret;

// Atlas-Befund unter der Einfügemarke des oberen Editors (#1886, F1 im Editor): Regel aus demselben Speicher wie
// Wellenlinien und Hover (TAtlasProblemsController.Current). Meldungen des Compilers zählen nicht, sie haben keine
// Regelseite. Nur im Hauptthread verwenden.

interface

type
  TAtlasIdeProblemAtCaret = class
  public
    /// <summary>Regel des ersten Atlas-Befunds an der Einfügemarke; False ohne.</summary>
    class function Rule(out ARule: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Problems.Store,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Problems.Controller;

function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and ((Result.Buffer = nil) or (Result.CursorPos.Line < 1)) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeProblemAtCaret.Rule(out ARule: string): Boolean;
var
  mView: IOTAEditView;
  mStore: TAtlasProblemStore;
  mCharacter: Integer;
  mProblem: TAtlasProblem;
begin
  Result := False;
  ARule := '';
  mView := TopView;
  mStore := TAtlasProblemsController.Current;
  if (mView = nil) or (mStore = nil) then
  begin
    Exit;
  end;
  mCharacter := TLspSessionJson.ColumnToIndex(TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line),
    mView.CursorPos.Col, TAtlasEditorBuffer.TabWidth(mView.Buffer));
  for mProblem in mStore.At(mView.Buffer.FileName, mView.CursorPos.Line - 1, mCharacter) do
  begin
    if (mProblem.Source <> TAtlasProblem.cCompilerSource) and (mProblem.Code <> '') then
    begin
      ARule := mProblem.Code;
      Exit(True);
    end;
  end;
end;

end.
