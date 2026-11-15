unit Atlas.Core.Debug.NoSourceFlow;

// Entscheidungen der Hilfe „Kein Quelltext“ (#869) außerhalb von Ursache und Wegen, ohne IDE prüfbar (#1967):
// welcher Halt geprüft wird, ob „Zurück zum eigenen Code“ weiterläuft, ob die Stelle ignoriert ist, unter welchem
// Namen sie ignoriert bzw. gesucht wird. Atlas.IDE.Debug.NoSource fragt Debugger, Einstellungen und Dateisystem.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.NoSource;

type
  TAtlasNoSourceFlow = class
  public
    /// <summary>Halt prüfen: Hilfe an (AEnabled); bei einer Pause mit „Nur eigener Code“ übernimmt #578 die
    /// Schritte, außer Atlas kehrt gerade zum eigenen Code zurück (AReturning).</summary>
    class function Watches(AEnabled, AReturning, APaused, AJustMyCode: Boolean): Boolean; static;
    /// <summary>Steht irgendwo im Stapel eigener Code?</summary>
    class function HasOwnFrame(const AFrames: TAtlasDebugFrames): Boolean; static;
    /// <summary>„Zurück zum eigenen Code“ weiter: oberster Rahmen fremd, eigener Code darunter und weniger als AMax
    /// Rückkehrschritte (AReturns)?</summary>
    class function KeepsReturning(const AFrames: TAtlasDebugFrames; AReturns, AMax: Integer): Boolean; static;
    /// <summary>Unit bzw. Modul von AFacts in der Liste AIgnored?</summary>
    class function Ignored(const AFacts: TAtlasNoSourceFacts; const AIgnored: string): Boolean; static;
    /// <summary>Name für „Nicht mehr anzeigen“: Unit, sonst Modul; '' ohne beide.</summary>
    class function IgnoreName(const AFacts: TAtlasNoSourceFacts): string; static;
    /// <summary>Gesuchte Datei für „Quelltext suchen“: Unit.pas, ohne Unit die Routine.</summary>
    class function SourceName(const AFacts: TAtlasNoSourceFacts): string; static;
    /// <summary>AValue, leer der Text AUnknown.</summary>
    class function OrUnknown(const AValue, AUnknown: string): string; static;
  end;

implementation

{ TAtlasNoSourceFlow }

class function TAtlasNoSourceFlow.Watches(AEnabled, AReturning, APaused, AJustMyCode: Boolean): Boolean;
begin
  Result := AEnabled and (AReturning or not APaused or not AJustMyCode);
end;

class function TAtlasNoSourceFlow.HasOwnFrame(const AFrames: TAtlasDebugFrames): Boolean;
var
  mFrame: TAtlasDebugFrame;
begin
  for mFrame in AFrames do
  begin
    if mFrame.Own then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasNoSourceFlow.KeepsReturning(const AFrames: TAtlasDebugFrames; AReturns, AMax: Integer): Boolean;
begin
  Result := (Length(AFrames) > 0) and not AFrames[0].Own and (AReturns < AMax) and HasOwnFrame(AFrames);
end;

class function TAtlasNoSourceFlow.Ignored(const AFacts: TAtlasNoSourceFacts; const AIgnored: string): Boolean;
begin
  Result := TAtlasNoSource.IsIgnored(AFacts.UnitName, AIgnored) or
    TAtlasNoSource.IsIgnored(AFacts.Place.Module, AIgnored);
end;

class function TAtlasNoSourceFlow.IgnoreName(const AFacts: TAtlasNoSourceFacts): string;
begin
  Result := AFacts.UnitName;
  if Result = '' then
  begin
    Result := AFacts.Place.Module;
  end;
end;

class function TAtlasNoSourceFlow.SourceName(const AFacts: TAtlasNoSourceFacts): string;
begin
  Result := AFacts.UnitName + '.pas';
  if AFacts.UnitName = '' then
  begin
    Result := AFacts.Place.Routine;
  end;
end;

class function TAtlasNoSourceFlow.OrUnknown(const AValue, AUnknown: string): string;
begin
  Result := AValue;
  if Result = '' then
  begin
    Result := AUnknown;
  end;
end;

end.
