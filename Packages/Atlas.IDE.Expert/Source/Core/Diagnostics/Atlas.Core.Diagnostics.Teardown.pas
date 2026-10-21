unit Atlas.Core.Diagnostics.Teardown;

// Abbau beim Entladen in Schritten (#886): Jeder Schritt läuft für sich; eine
// Ausnahme bricht den Abbau nicht ab. Früher endete Unregister beim ersten
// Fehler, etwa wenn die IDE Atlas mitten im Gruppen-Build entlud. Dann blieben
// Notifier, Fenster-Hooks und Ereignisse der alten Instanz angemeldet, und die
// IDE stürzte beim Beenden in fremdem Speicher ab; „Atlas entladen“ fehlte im
// Protokoll. Festgehalten werden nur Schritt und Ausnahmeklasse, nie der
// Meldungstext, weil er Pfade enthalten kann (anonymes Protokoll).

interface

uses
  System.SysUtils;

type
  TAtlasTeardown = record
  private
    FFailures: TArray<string>;
  public
    /// <summary>Leerer Abbau ohne Fehler.</summary>
    class function Create: TAtlasTeardown; static;
    /// <summary>AStep ausführen; eine Ausnahme wird als „AName: Klasse“ vermerkt und nicht weitergereicht.</summary>
    procedure Step(const AName: string; const AStep: TProc);
    /// <summary>Fehler eines anderen Abbaus (etwa der Feature-Tabelle) übernehmen.</summary>
    procedure AddFailures(const AFailures: TArray<string>);
    /// <summary>Fehlgeschlagene Schritte in Reihenfolge, je „Name: Klasse“.</summary>
    function Failures: TArray<string>;
    /// <summary>„keine“ bzw. die fehlgeschlagenen Schritte mit Komma getrennt.</summary>
    function Summary: string;
  end;

implementation

{ TAtlasTeardown }

class function TAtlasTeardown.Create: TAtlasTeardown;
begin
  Result.FFailures := nil;
end;

procedure TAtlasTeardown.Step(const AName: string; const AStep: TProc);
begin
  try
    if Assigned(AStep) then
      AStep();
  except
    on E: Exception do
      FFailures := FFailures + [AName + ': ' + E.ClassName];
  end;
end;

procedure TAtlasTeardown.AddFailures(const AFailures: TArray<string>);
begin
  FFailures := FFailures + AFailures;
end;

function TAtlasTeardown.Failures: TArray<string>;
begin
  Result := FFailures;
end;

function TAtlasTeardown.Summary: string;
begin
  if Length(FFailures) = 0 then
    Result := 'keine'
  else
    Result := string.Join(', ', FFailures);
end;

end.
