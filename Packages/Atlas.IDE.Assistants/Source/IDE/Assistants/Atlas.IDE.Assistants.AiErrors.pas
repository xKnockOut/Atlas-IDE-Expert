unit Atlas.IDE.Assistants.AiErrors;

// Texte zu den Fehlern der KI-Anbieter (TAtlasAiError) für Schattentext, Text für andere Module und die Proben der
// Optionsseite. Steht für sich, damit die Adapter des Moduls einander nicht einbinden.

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  TAtlasAiErrorTexts = record
  public
    /// <summary>Text zum Fehler AError; '' ohne Fehler.</summary>
    class function Text(AError: TAtlasAiError): string; static;
  end;

implementation

uses
  Atlas.UI.Assistants.Strings;

{ TAtlasAiErrorTexts }

class function TAtlasAiErrorTexts.Text(AError: TAtlasAiError): string;
begin
  case AError of
    TAtlasAiError.NoKey:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorNoKey);
    TAtlasAiError.Unreachable:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorUnreachable);
    TAtlasAiError.Timeout:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorTimeout);
    TAtlasAiError.Unauthorized:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorUnauthorized);
    TAtlasAiError.ModelMissing:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorModelMissing);
    TAtlasAiError.RateLimited:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorRateLimited);
    TAtlasAiError.ServerError:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorServerError);
    TAtlasAiError.BadAnswer:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorBadAnswer);
    TAtlasAiError.Cancelled:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorCancelled);
    TAtlasAiError.Refused:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorRefused);
  else
    Result := '';
  end;
end;

end.
