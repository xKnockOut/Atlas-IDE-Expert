unit Atlas.Core.Assistants.IdeProviders;

// KI-Anbieter der IDE (Smart CodeInsight, #2744), wie das Modul KI-Assistenten sie sieht: Name, aktiv und die
// Funktionen, die Atlas braucht (Records und Vertrag in Atlas.Core.Assistants.Contract.IdeAi). Hier steht nur,
// welcher Anbieter einfache Aufgaben übernimmt.
// - Der eigene Eintrag von Atlas in der Liste der IDE (#2745, „Atlas (…)“) wird nie gewählt: Sonst ginge eine
//   Anfrage im Kreis.
// - Gewünschter Name leer: der erste aktive Anbieter mit Anweisung oder Chat.
// - Gewünschter Name gesetzt: nur dieser, ohne Rücksicht auf Groß- und Kleinschreibung; fehlt er oder ist er aus,
//   gibt es keine Quelle (kein stiller Wechsel zu einem anderen Dienst).

interface

uses
  Atlas.Core.Assistants.Contract.IdeAi;

type
  TAtlasIdeAiProviders = class
  public const
    /// <summary>Anfang des Namens, unter dem Atlas sich selbst bei der IDE anmeldet (#2745).</summary>
    cOwnPrefix = 'Atlas (';
  public
    /// <summary>AName ist der eigene Eintrag von Atlas.</summary>
    class function IsOwn(const AName: string): Boolean; static;
    /// <summary>Anbieter für einfache Aufgaben nach dem gewünschten Namen; False ohne passenden.</summary>
    class function Pick(const AProviders: TArray<TAtlasIdeAiProvider>; const AWanted: string;
      out AProvider: TAtlasIdeAiProvider): Boolean; static;
    /// <summary>Name des eigenen Eintrags: „Atlas (AProvider)“.</summary>
    class function OwnName(const AProvider: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasIdeAiProviders }

class function TAtlasIdeAiProviders.IsOwn(const AName: string): Boolean;
begin
  Result := AName.StartsWith(cOwnPrefix, True);
end;

class function TAtlasIdeAiProviders.OwnName(const AProvider: string): string;
begin
  Result := cOwnPrefix + AProvider + ')';
end;

class function TAtlasIdeAiProviders.Pick(const AProviders: TArray<TAtlasIdeAiProvider>; const AWanted: string;
  out AProvider: TAtlasIdeAiProvider): Boolean;
var
  mProvider: TAtlasIdeAiProvider;
  mWanted: string;
begin
  AProvider := Default(TAtlasIdeAiProvider);
  mWanted := Trim(AWanted);
  for mProvider in AProviders do
  begin
    if IsOwn(mProvider.Name) or not mProvider.Usable then
    begin
      Continue;
    end;
    if (mWanted = '') or SameText(mProvider.Name, mWanted) then
    begin
      AProvider := mProvider;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
