unit Atlas.Core.Problems.Prompt;

// „Als Auftrag für KI-Assistenten kopieren“ im Fenster „Atlas-Prüfung“ (#2570), Kern ohne VCL: Argumente des
// Serverbefehls atlas.server.findingsPrompt aus den markierten Befunden und der Text aus der Antwort. Den Auftrag
// erzeugt der Server (TFindingPrompt), weil nur er Regelkatalog und Editorpuffer hat; das Plugin baut keinen
// zweiten Text.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Problems.Findings;

type
  TAtlasFindingsPrompt = class
  public const
    cCommand = 'atlas.server.findingsPrompt';
  public
    /// <summary>Argumente des Befehls: [{"findings": [{"file", "line", "character", "rule", "message",
    /// "severity", "compiler"}, …]}] als JSON.</summary>
    class function Arguments(const AFindings: TArray<TAtlasFinding>): string; static;
    /// <summary>Auftrag aus der Antwort des Servers; '' ohne Antwort oder ohne Text.</summary>
    class function TextOf(const AAnswer: TJSONValue): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Core.Lsp.Contract;

const
  cSeverityNames: array[TAtlasProblemSeverity] of string = ('error', 'warning', 'info', 'hint');

/// <summary>Ein Befund als Objekt für den Server.</summary>
function FindingJson(const AFinding: TAtlasFinding): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AFinding.FileName);
  Result.AddPair('line', TJSONNumber.Create(AFinding.Problem.StartLine));
  Result.AddPair('character', TJSONNumber.Create(AFinding.Problem.StartCharacter));
  Result.AddPair('rule', AFinding.Rule);
  Result.AddPair('message', AFinding.Problem.Message);
  Result.AddPair('severity', cSeverityNames[AFinding.Problem.Severity]);
  Result.AddPair('compiler', TJSONBool.Create(AFinding.Category = TAtlasFindingCategory.Compiler));
end;

{ TAtlasFindingsPrompt }

class function TAtlasFindingsPrompt.Arguments(const AFindings: TArray<TAtlasFinding>): string;
var
  mRoot: TJSONArray;
  mArguments: TJSONObject;
  mFindings: TJSONArray;
  mFinding: TAtlasFinding;
begin
  mRoot := TJSONArray.Create;
  try
    mArguments := TJSONObject.Create;
    mRoot.AddElement(mArguments);
    mFindings := TJSONArray.Create;
    mArguments.AddPair('findings', mFindings);
    for mFinding in AFindings do
    begin
      mFindings.AddElement(FindingJson(mFinding));
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasFindingsPrompt.TextOf(const AAnswer: TJSONValue): string;
begin
  Result := '';
  if AAnswer is TJSONObject then
  begin
    Result := TJSONObject(AAnswer).GetValue<string>('text', '');
  end;
end;

end.
