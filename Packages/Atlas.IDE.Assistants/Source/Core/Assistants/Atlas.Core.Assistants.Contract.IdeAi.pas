unit Atlas.Core.Assistants.Contract.IdeAi;

// Vertrag zwischen dem Modul KI-Assistenten und den Adaptern über ToolsAPI.AI (Smart CodeInsight, #2744, #2745):
// - TAtlasIdeAiProvider und IAtlasIdeAiEngine: Anbieter der IDE und Anfragen an sie (#2744); der Adapter
//   Atlas.IDE.Assistants.Adapters.IdeProviders setzt sie über ToolsAPI.AI um, Tests fälschen sie.
// - IAtlasIdeAiAnswers: ein Notifier der IDE, wie die Brücke Atlas.IDE.Assistants.IdeBridge ihn sieht (#2745); der
//   Adapter Atlas.IDE.Assistants.Adapters.IdePlugin reicht die Rückmeldungen an IOTAAIServicesNotifier weiter.
// Nur Records und Interfaces.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Funktionen eines Anbieters der IDE, soweit Atlas sie nutzt oder anbietet.</summary>
  TAtlasIdeAiFeature = (Chat, Instruction, ListModels);
{$SCOPEDENUMS OFF}
  TAtlasIdeAiFeatures = set of TAtlasIdeAiFeature;

  /// <summary>Ein Anbieter der IDE.</summary>
  TAtlasIdeAiProvider = record
    Name: string;
    Enabled: Boolean;
    Features: TAtlasIdeAiFeatures;
    /// <summary>Aktiv und kann Text beantworten (Anweisung oder Chat).</summary>
    function Usable: Boolean;
    class function Make(const AName: string; AEnabled: Boolean; AFeatures: TAtlasIdeAiFeatures):
      TAtlasIdeAiProvider; static;
  end;

  /// <summary>Anbieter der IDE samt Anfragen; Adapter über ToolsAPI.AI, in Tests gefälscht. Alle Aufrufe im
  /// Hauptthread.</summary>
  IAtlasIdeAiEngine = interface
    ['{B3C5E2A7-6D41-4F98-9A0E-2C7F15D8B640}']
    function Providers: TArray<TAtlasIdeAiProvider>;
    /// <summary>Anweisung an den Anbieter AName. Ergebnis: Kennung der Anfrage, '' wenn der Anbieter fehlt oder
    /// ablehnt. Die Antwort kommt über den Rückruf, den der Adapter beim Anlegen bekam.</summary>
    function Instruction(const AName, AInput, AInstruction: string): string;
    /// <summary>Frage an den Anbieter AName; Ergebnis wie bei Instruction.</summary>
    function Chat(const AName, AQuestion: string): string;
    /// <summary>Alle laufenden Anfragen des Anbieters AName abbrechen (die IDE kennt keinen Abbruch je Anfrage).
    /// </summary>
    procedure Cancel(const AName: string);
  end;

  /// <summary>Ein Notifier der IDE, wie die Brücke ihn sieht.</summary>
  IAtlasIdeAiAnswers = interface
    ['{6A1F0C93-2E57-4B8D-A4C6-93D7E05B21F8}']
    procedure Answer(const AText, AId: string);
    procedure Error(const AText, AId: string);
    procedure Models(const AModels: TArray<string>; const AId: string);
  end;

implementation

{ TAtlasIdeAiProvider }

function TAtlasIdeAiProvider.Usable: Boolean;
begin
  Result := Enabled and ((TAtlasIdeAiFeature.Instruction in Features) or (TAtlasIdeAiFeature.Chat in Features));
end;

class function TAtlasIdeAiProvider.Make(const AName: string; AEnabled: Boolean; AFeatures: TAtlasIdeAiFeatures):
  TAtlasIdeAiProvider;
begin
  Result := Default(TAtlasIdeAiProvider);
  Result.Name := AName;
  Result.Enabled := AEnabled;
  Result.Features := AFeatures;
end;

end.
