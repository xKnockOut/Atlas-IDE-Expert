unit Atlas.Core.Debug.WhyHereFlow;

// Entscheidungen von „Warum bin ich hier?“ (#1878) und der Vorhersage (#2169) außerhalb der Blöcke, ohne IDE
// prüfbar (#1967): welcher Teil als Nächstes ausgewertet wird, was am Zeilenende steht und was ein Klick auf den
// Text tut. Atlas.IDE.Debug.WhyHere fragt Debugger, Server und Editor.

interface

uses
  Atlas.Core.Debug.WhyHere,
  Atlas.Core.Debug.Forecast;

{$SCOPEDENUMS ON}

type
  /// <summary>Klick auf den Text einer Zeile: nichts, Rückfrage zu den Aufrufen, Menü der Vorhersage.</summary>
  TAtlasWhyHereClick = (None, Calls, Forecast);

  TAtlasWhyHereFlow = class
  public
    /// <summary>Nächster Teil zum Auswerten: erst „Warum bin ich hier?“ (AWhy), dann die Vorhersage
    /// (AForecast, AIsForecast = True). False, wenn nichts mehr aussteht.</summary>
    class function NextOf(AWhy: TAtlasWhyHere; AForecast: TAtlasForecast; out ARef: TAtlasWhyHereRef;
      out AIsForecast: Boolean): Boolean; static;
    /// <summary>Text am Zeilenende: „Warum bin ich hier?“, dann die Vorhersage; '' ohne beide.</summary>
    class function LineText(const AWhyText, AForecastText: string): string; static;
    /// <summary>Aufrufe gehen vor (Rückfrage), sonst das Menü der Vorhersage, wenn die Zeile eine hat.</summary>
    class function Click(ACallCount: Integer; const AForecastText: string): TAtlasWhyHereClick; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasWhyHereFlow }

class function TAtlasWhyHereFlow.NextOf(AWhy: TAtlasWhyHere; AForecast: TAtlasForecast; out ARef: TAtlasWhyHereRef;
  out AIsForecast: Boolean): Boolean;
begin
  AIsForecast := False;
  Result := AWhy.NextPending(ARef);
  if not Result then
  begin
    AIsForecast := True;
    Result := AForecast.NextPending(ARef);
  end;
end;

class function TAtlasWhyHereFlow.LineText(const AWhyText, AForecastText: string): string;
begin
  Result := Trim(AWhyText + '  ' + AForecastText);
end;

class function TAtlasWhyHereFlow.Click(ACallCount: Integer; const AForecastText: string): TAtlasWhyHereClick;
begin
  if ACallCount > 0 then
  begin
    Result := TAtlasWhyHereClick.Calls;
  end
  else if AForecastText <> '' then
  begin
    Result := TAtlasWhyHereClick.Forecast;
  end
  else
  begin
    Result := TAtlasWhyHereClick.None;
  end;
end;

end.
